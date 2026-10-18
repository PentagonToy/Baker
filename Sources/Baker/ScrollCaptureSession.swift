import BakerCore
import AppKit
import ScreenCaptureKit
import SwiftUI
import VideoToolbox

/// The stream owns three surfaces; Baker retains only the most recent one until sampling.
private final class ScrollStreamFrames: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var revision = 0
    private var changedAt: TimeInterval = 0
    private var failure: Error?
    private var closed = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sample),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        lock.withLock {
            guard !closed else { return }
            latest = buffer; revision += 1; changedAt = ProcessInfo.processInfo.systemUptime
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { lock.withLock { if !closed { failure = error } } }

    var settled: Bool { lock.withLock { revision > 0 && ProcessInfo.processInfo.systemUptime - changedAt >= 0.24 } }

    func image(after acceptedRevision: Int) throws -> (CGImage, Int)? {
        let snapshot: (CVPixelBuffer?, Int, TimeInterval, Error?) = lock.withLock { (latest, revision, changedAt, failure) }
        if let error = snapshot.3 { throw error }
        guard let buffer = snapshot.0, snapshot.1 != acceptedRevision else { return nil }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr, let image else {
            throw BakerError(message: "Could not read the scrolling capture frame.", code: .captureFailed)
        }
        // Borrow the surface for this sample. The stitcher copies only accepted rows;
        // signatures and the small preview do not retain the capture buffer.
        return (image, snapshot.1)
    }
    func close() { lock.withLock { closed = true; latest = nil } }
}

private actor ScrollAssembler {
    private var buffer = ScrollCaptureBuffer()
    private var sampledRevision = 0
    private var previewCanvas: CGImage?

    func sample(_ frames: ScrollStreamFrames) throws -> (StitchOutcome, Int, Int, CGImage?)? {
        try autoreleasepool { try sampleFrame(frames) }
    }
    private func sampleFrame(_ frames: ScrollStreamFrames) throws -> (StitchOutcome, Int, Int, CGImage?)? {
        guard let (image, revision) = try frames.image(after: sampledRevision) else { return nil }
        sampledRevision = revision
        // Match sharp captured frames continuously; overlap validation rejects unsafe samples.
        guard let outcome = try buffer.observe(image, allowMoving: true) else { return nil }
        let previewSource: CGImage
        if case .appended(let pixels) = outcome {
            previewSource = image.cropping(to: CGRect(x: 0, y: image.height - pixels, width: image.width, height: pixels)) ?? image
        } else if outcome == .started { previewSource = image }
        else { return (outcome, buffer.acceptedFrames, buffer.height, nil) }
        let scale = min(1, 200.0 / Double(previewSource.width))
        let width = max(1, Int(Double(previewSource.width) * scale))
        let stripHeight = max(1, Int(ceil(Double(previewSource.height) * scale)))
        let previousHeight = previewCanvas?.height ?? 0
        let height = min(600, previousHeight + stripHeight)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "Could not prepare the scrolling preview.", code: .captureFailed)
        }
        context.interpolationQuality = .high
        if let previous = previewCanvas {
            context.draw(previous, in: CGRect(x: 0, y: stripHeight, width: width, height: previousHeight))
        }
        context.draw(previewSource, in: CGRect(x: 0, y: 0, width: width, height: stripHeight))
        guard let preview = context.makeImage() else { throw BakerError(message: "Could not prepare the scrolling preview.", code: .captureFailed) }
        previewCanvas = preview
        return (outcome, buffer.acceptedFrames, buffer.height, preview)
    }
    func finish() throws -> CGImage? { return try buffer.finish() }
    func cancel() { buffer.cancel(); previewCanvas = nil }
}

@MainActor
final class ScrollCaptureSession: ObservableObject {
    enum State { case idle, preparing, capturing, finishing, completed, cancelled, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var message = "Preparing the first frame…"
    @Published private(set) var count = 0
    @Published private(set) var height = 0
    @Published private(set) var preview: NSImage?
    @Published private(set) var elapsed = 0
    private var task: Task<Void, Never>?
    private var panel: NSPanel?
    private var finishRequestedAt: TimeInterval?
    private var cancelled = false
    private var completion: ((Result<CGImage?, Error>) -> Void)?

    func start(capture: PreparedCapture, region: CaptureRegion, targetApplication: NSRunningApplication? = nil,
               completion: @escaping (Result<CGImage?, Error>) -> Void) {
        guard state == .idle else {
            completion(.failure(BakerError(message: "This scrolling session has already been used.", code: .invalidState))); return
        }
        state = .preparing; self.completion = completion
        showControls(region: region)
        targetApplication?.activate()
        let frames = ScrollStreamFrames()
        let assembler = ScrollAssembler()
        task = Task { [self] in
            var stream: SCStream?
            do {
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = region.rect
                configuration.width = capture.configuration.width; configuration.height = capture.configuration.height
                guard configuration.width >= 80, configuration.height >= 100 else {
                    throw BakerError(message: "Select a scrolling region at least 80 × 100 pixels, excluding fixed headers and scrollbars.", code: .invalidInput)
                }
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.captureResolution = .best
                configuration.showsCursor = false; configuration.capturesAudio = false
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                configuration.queueDepth = 3
                let value = SCStream(filter: capture.filter, configuration: configuration, delegate: frames)
                stream = value
                try value.addStreamOutput(frames, type: .screen,
                    sampleHandlerQueue: DispatchQueue(label: "baker.scroll.frames", qos: .userInitiated))
                try Task.checkCancellation()
                try await value.startCapture()
                let started = ProcessInfo.processInfo.systemUptime
                state = .capturing
                while !Task.isCancelled && !cancelled {
                    let now = ProcessInfo.processInfo.systemUptime
                    elapsed = Int(now - started)
                    if elapsed >= 300 { message = "Time limit reached. Assembling the saved portion…"; break }
                    if let update = try await assembler.sample(frames) {
                        try Task.checkCancellation()
                        let (outcome, count, height, thumbnail) = update
                        self.count = count; self.height = height
                        switch outcome {
                        case .started:
                            if let thumbnail { preview = NSImage(cgImage: thumbnail, size: .zero) }
                            message = "First frame ready. Scroll down inside the selected area."
                        case .appended(let pixels):
                            if let thumbnail { preview = NSImage(cgImage: thumbnail, size: .zero) }
                            message = "+\(pixels) px added. Keep scrolling down, or finish."
                        case .unchanged: break
                        case .rejected(let reason): message = reason
                        }
                    }
                    if let requested = finishRequestedAt, frames.settled || now - requested >= 0.8 { break }
                    if count == 0 && now - started > 5 { throw BakerError(message: "No screen frame arrived. Check Screen Recording permission and try again.", code: .captureFailed) }
                    try await Task.sleep(nanoseconds: 16_000_000)
                }
                state = .finishing
                try await value.stopCapture(); stream = nil
                frames.close()
                if cancelled || Task.isCancelled {
                    await assembler.cancel(); complete(.success(nil), state: .cancelled)
                } else {
                    message = "Assembling \(height) px…"
                    let image = try await assembler.finish()
                    if cancelled || Task.isCancelled { complete(.success(nil), state: .cancelled) }
                    else { complete(.success(image), state: .completed) }
                }
            } catch {
                if let stream { try? await stream.stopCapture() }
                frames.close(); await assembler.cancel()
                if cancelled || error is CancellationError { complete(.success(nil), state: .cancelled) }
                else { complete(.failure(error), state: .failed) }
            }
        }
    }

    func finish() {
        guard state == .capturing, count > 0, finishRequestedAt == nil else { return }
        state = .finishing
        finishRequestedAt = ProcessInfo.processInfo.systemUptime
        message = "Finishing after the page settles…"
    }
    func cancel() {
        guard state == .preparing || state == .capturing || state == .finishing else { return }
        cancelled = true; task?.cancel(); message = "Cancelling…"
    }
    func cancelAndWait() async { let running = task; cancel(); await running?.value }

    private func complete(_ result: Result<CGImage?, Error>, state: State) {
        guard completion != nil else { return }
        self.state = state
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        let callback = completion; completion = nil; task = nil
        callback?(result)
    }

    private func showControls(region: CaptureRegion) {
        let visible = region.screen.visibleFrame
        let selected = CGRect(x: region.screen.frame.minX + region.rect.minX,
            y: region.screen.frame.maxY - region.rect.maxY, width: region.rect.width, height: region.rect.height)
        let size = CGSize(width: min(420, visible.width - 24), height: 184)
        let candidates = [
            CGPoint(x: selected.minX, y: selected.minY - size.height - 12),
            CGPoint(x: selected.minX, y: selected.maxY + 12),
            CGPoint(x: selected.maxX + 12, y: selected.minY),
            CGPoint(x: selected.minX - size.width - 12, y: selected.minY),
            CGPoint(x: visible.maxX - size.width - 12, y: visible.minY + 12)
        ].map { point in CGRect(x: min(max(point.x, visible.minX + 12), visible.maxX - size.width - 12),
            y: min(max(point.y, visible.minY + 12), visible.maxY - size.height - 12), width: size.width, height: size.height) }
        let placement = candidates.min { left, right in
            let a = left.intersection(selected), b = right.intersection(selected)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }!
        let panel = NSPanel(contentRect: placement, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.title = "Baker · Scrolling capture"; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = ScrollHostingView(rootView: ScrollControls(session: self))
        panel.orderFrontRegardless(); self.panel = panel
    }
}

@MainActor
private final class ScrollHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ScrollControls: View {
    @ObservedObject var session: ScrollCaptureSession
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.08))
                if let image = session.preview { Image(nsImage: image).resizable().scaledToFit().padding(4) }
                else { ProgressView().controlSize(.small) }
            }.frame(width: 92, height: 146)
            VStack(alignment: .leading, spacing: 9) {
                Text("Scrolling capture").font(BakerTypography.section)
                Text(session.message).font(BakerTypography.body).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(session.count) sections · \(session.height) px · \(session.elapsed)s")
                    .font(BakerTypography.supporting.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 4)
                    Button("Cancel", action: session.cancel).buttonStyle(.plain)
                    Button("Finish", action: session.finish).buttonStyle(.borderedProminent).tint(.accentColor)
                        .disabled(session.count == 0 || session.state != .capturing)
                }
            }
        }.padding(14).frame(height: 184)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}
