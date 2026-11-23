import BakerCore
import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI
import VideoToolbox

struct ScrollAdvanceProgress {
    enum Decision { case advance, finished, paused }
    private var previousHeight = 0
    private var unchanged = 0
    private var advanced = false
    func isReady(height: Int, settled: Bool, overdue: TimeInterval) -> Bool {
        settled || height > previousHeight || overdue >= 0.6
    }
    mutating func observe(height: Int, rejected: Bool) -> Decision {
        if height > previousHeight { advanced = advanced || previousHeight > 0; unchanged = 0; previousHeight = height }
        else { unchanged += 1 }
        if rejected { return .paused }
        return unchanged >= 3 ? (advanced ? .finished : .paused) : .advance
    }
}

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
        let scale = min(1, 200.0 / Double(buffer.width), 600.0 / Double(buffer.height))
        let width = max(1, Int(Double(previewSource.width) * scale))
        let stripHeight = max(1, Int(ceil(Double(previewSource.height) * scale)))
        let height = max(1, Int(ceil(Double(buffer.height) * scale)))
        let previousHeight = max(0, height - stripHeight)
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
    @Published private(set) var caption = "Preparing…"
    @Published private(set) var count = 0
    @Published private(set) var width = 0
    @Published private(set) var height = 0
    @Published private(set) var preview: NSImage?
    @Published private(set) var elapsed = 0
    @Published private(set) var autoScrolling = false
    private var autoTarget: ScanTurnTarget?
    private var targetApplication: NSRunningApplication?
    private var region: CaptureRegion?
    private var autoProgress = ScrollAdvanceProgress()
    private var nextAutoScrollAt: TimeInterval = 0
    private var autoRejected = false
    private var alignmentIssue: String?
    private var scrollEventsPosted = 0
    private var autoRequests = 0
    private var lastAutoIssue: String?
    private var autoSetupTask: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private var panel: NSPanel?
    private var outline: NSPanel?
    private var previewPanel: NSPanel?
    private var finishRequestedAt: TimeInterval?
    private var cancelled = false
    private var completion: ((Result<CGImage?, Error>) -> Void)?
    static var permissions: [String: Any] {
        ["accessibilityAllowed": AXIsProcessTrusted(), "eventPostingAllowed": CGPreflightPostEventAccess()]
    }
    var resourceState: [String: Any] {
        var result: [String: Any] = ["state": String(describing: state), "automatic": autoScrolling,
            "caption": caption, "message": message, "acceptedFrames": count, "width": width, "height": height,
            "scrollEventsPosted": scrollEventsPosted]
        result["autoRequests"] = autoRequests
        if let lastAutoIssue { result["lastAutoIssue"] = lastAutoIssue }
        result.merge(Self.permissions) { _, value in value }
        if let alignmentIssue { result["alignmentIssue"] = alignmentIssue }
        if let region { result["pointerInside"] = RecordingPlacement.selection(region.rect, on: region.screen.frame).contains(NSEvent.mouseLocation) }
        if let application = targetApplication {
            result["targetPID"] = application.processIdentifier
            result["targetIsFrontmost"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        }
        return result
    }

    func start(capture: PreparedCapture, region: CaptureRegion, targetApplication: NSRunningApplication? = nil,
               completion: @escaping (Result<CGImage?, Error>) -> Void) {
        guard state == .idle else {
            completion(.failure(BakerError(message: "This scrolling session has already been used.", code: .invalidState))); return
        }
        state = .preparing; self.completion = completion
        self.targetApplication = targetApplication; self.region = region
        if panel == nil { prepareControls(region: region) }
        width = capture.configuration.width
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
                var reachedLimit = false
                while !Task.isCancelled && !cancelled {
                    let now = ProcessInfo.processInfo.systemUptime
                    let seconds = Int(now - started)
                    if elapsed != seconds { elapsed = seconds }
                    if elapsed >= 300 { message = "Time limit reached. Assembling the saved portion…"; break }
                    if let update = try await assembler.sample(frames) {
                        try Task.checkCancellation()
                        let (outcome, count, height, thumbnail) = update
                        if self.count != count { self.count = count }
                        if self.height != height { self.height = height }
                        switch outcome {
                        case .started:
                            if let thumbnail { preview = NSImage(cgImage: thumbnail, size: .zero) }
                            message = "Scroll down inside the selection."
                            caption = "Scroll to capture"
                        case .appended:
                            if let thumbnail { preview = NSImage(cgImage: thumbnail, size: .zero) }
                            message = "Scroll down, then choose Done."
                            caption = autoScrolling ? "Auto Scroll" : "Capturing"; autoRejected = false; alignmentIssue = nil
                        case .unchanged: break
                        case .rejected(let reason): message = reason; alignmentIssue = reason; caption = "Alignment lost"; if autoScrolling { autoRejected = true }
                        case .limitReached:
                            message = "Image limit reached. Saving the captured portion…"
                            reachedLimit = true
                        }
                    }
                    if reachedLimit { break }
                    advanceAutomatically(now: now, settled: frames.settled)
                    if let requested = finishRequestedAt, frames.settled || now - requested >= 0.8 { break }
                    if count == 0 && now - started > 5 { throw BakerError(message: "No screen frame arrived. Check Screen Recording permission and try again.", code: .captureFailed) }
                    // Spend the frame budget on matching instead of adding another fixed delay.
                    let interval = autoScrolling || frames.settled ? 1.0 / 30 : 1.0 / 60
                    let remaining = interval - (ProcessInfo.processInfo.systemUptime - now)
                    if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                    else { await Task.yield() }
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
        autoSetupTask?.cancel(); autoSetupTask = nil
        autoScrolling = false; autoTarget = nil; state = .finishing; caption = "Saving…"
        finishRequestedAt = ProcessInfo.processInfo.systemUptime
        message = "Finishing after the page settles…"
    }
    func cancel() {
        autoSetupTask?.cancel(); autoSetupTask = nil
        if task == nil { closeControls(); return }
        guard state == .preparing || state == .capturing || state == .finishing else { return }
        autoScrolling = false; autoTarget = nil
        cancelled = true; task?.cancel(); message = "Cancelling…"
    }
    func cancelAndWait() async { let running = task; cancel(); await running?.value }

    func toggleAutoScroll() {
        autoRequests += 1
        guard state == .capturing, count > 0 else { return }
        if autoScrolling {
            autoSetupTask?.cancel(); autoSetupTask = nil
            autoScrolling = false; autoTarget = nil; caption = "Paused"; message = "Auto Scroll paused. Scroll manually or resume."; return
        }
        guard let application = targetApplication, let region else { message = "Focus the window to scroll, then start a new capture."; return }
        let attempt = autoRequests
        autoScrolling = true; lastAutoIssue = nil; caption = "Starting…"
        autoSetupTask = Task { [weak self] in
            guard let self else { return }
            defer { if autoRequests == attempt { autoSetupTask = nil } }
            do {
                try Task.checkCancellation()
                guard state == .capturing, autoScrolling, autoRequests == attempt else { return }
                // Clicking the floating controls can take focus from the reader.
                application.activate()
                for _ in 0..<15 {
                    try Task.checkCancellation()
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier { break }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                try Task.checkCancellation()
                guard state == .capturing, autoScrolling, autoRequests == attempt else { return }
                autoTarget = try ScanTurnTarget(application: application, region: region, point: nil, expectedWindow: nil, expectedTitle: nil)
                autoProgress = ScrollAdvanceProgress(); autoRejected = false
                let now = ProcessInfo.processInfo.systemUptime
                nextAutoScrollAt = now
                caption = "Auto Scroll"; message = "Scrolling automatically…"
                advanceAutomatically(now: now, settled: true)
            } catch {
                guard state == .capturing, autoScrolling, autoRequests == attempt, !(error is CancellationError) else { return }
                autoScrolling = false; autoTarget = nil; caption = "Control unavailable"
                lastAutoIssue = error.localizedDescription; message = error.localizedDescription
            }
        }
    }

    private func advanceAutomatically(now: TimeInterval, settled: Bool) {
        guard autoScrolling, state == .capturing, let target = autoTarget, let region,
              now >= nextAutoScrollAt,
              autoProgress.isReady(height: height, settled: settled, overdue: now - nextAutoScrollAt) else { return }
        switch autoProgress.observe(height: height, rejected: autoRejected) {
        case .finished: finish(); return
        case .paused:
            autoScrolling = false; autoTarget = nil
            caption = "Paused"; message = "No scrolling detected or alignment was lost. Scroll manually or choose a different region."
            lastAutoIssue = message; return
        case .advance: break
        }
        do {
            let top = NSScreen.screens.first?.frame.maxY ?? region.screen.frame.maxY
            let point = CGPoint(x: region.screen.frame.minX + region.rect.midX,
                y: top - region.screen.frame.maxY + region.rect.midY)
            try target.scroll(pixels: Int32(min(80, region.rect.height / 8)), at: point)
            scrollEventsPosted += 1
            nextAutoScrollAt = now + 0.15
            caption = "Auto Scroll"; message = "Scrolling automatically. Choose Pause to scroll manually."
        } catch { autoScrolling = false; autoTarget = nil; caption = "Paused"; lastAutoIssue = error.localizedDescription; message = error.localizedDescription }
    }

    private func complete(_ result: Result<CGImage?, Error>, state: State) {
        guard completion != nil else { return }
        self.state = state
        autoSetupTask?.cancel(); autoSetupTask = nil
        autoScrolling = false
        closeControls()
        preview = nil
        let callback = completion; completion = nil; task = nil
        callback?(result)
        autoTarget = nil; targetApplication = nil; region = nil
    }

    private func closeControls() {
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        outline?.orderOut(nil); outline?.contentView = nil; outline = nil
        previewPanel?.orderOut(nil); previewPanel?.contentView = nil; previewPanel = nil
    }
    func prepareControls(region: CaptureRegion) {
        guard panel == nil else { return }
        let visible = region.screen.visibleFrame
        let selected = CGRect(x: region.screen.frame.minX + region.rect.minX,
            y: region.screen.frame.maxY - region.rect.maxY, width: region.rect.width, height: region.rect.height)
        let size = CGSize(width: min(460, visible.width - 24), height: 52)
        let candidates = [
            CGPoint(x: selected.midX - size.width / 2, y: selected.minY - size.height - 12),
            CGPoint(x: selected.midX - size.width / 2, y: selected.maxY + 12),
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
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = false
        panel.title = "Baker · Scrolling capture"; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = ScrollHostingView(rootView: ScrollControls(session: self))
        panel.orderFrontRegardless(); self.panel = panel
        let outline = NSPanel(contentRect: selected.insetBy(dx: -2, dy: -2), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        outline.isReleasedWhenClosed = false; outline.isOpaque = false; outline.backgroundColor = .clear
        outline.ignoresMouseEvents = true; outline.level = .floating; outline.hidesOnDeactivate = false
        outline.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let border = NSView()
        border.wantsLayer = true; border.layer?.borderWidth = 2
        border.layer?.borderColor = NSColor(BakerTheme.accent).cgColor
        outline.contentView = border; outline.orderFrontRegardless(); self.outline = outline
        let previewSize = CGSize(width: 136, height: 208)
        let left = selected.minX - previewSize.width - 12
        let right = selected.maxX + 12
        let previewX = left >= visible.minX + 12 ? left : right + previewSize.width <= visible.maxX - 12 ? right : visible.maxX - previewSize.width - 12
        let previewFrame = CGRect(x: previewX, y: min(max(selected.minY, visible.minY + 12), visible.maxY - previewSize.height - 12), width: previewSize.width, height: previewSize.height)
        let preview = NSPanel(contentRect: previewFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false; preview.isOpaque = false; preview.backgroundColor = .clear
        preview.level = .floating; preview.hidesOnDeactivate = false; preview.hasShadow = true; preview.ignoresMouseEvents = true
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        preview.contentView = NSHostingView(rootView: ScrollCapturePreview(session: self))
        preview.orderFrontRegardless(); previewPanel = preview
    }
}

@MainActor
private final class ScrollHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct ScrollControls: View {
    @ObservedObject var session: ScrollCaptureSession
    var body: some View {
        HStack(spacing: 8) {
            Button(action: session.cancel) { Image(systemName: "xmark").frame(width: 16) }
                .keyboardShortcut(.cancelAction).help("Cancel capture").accessibilityLabel("Cancel capture")
            Button(action: session.toggleAutoScroll) {
                Label(session.autoScrolling ? "Pause" : "Auto Scroll", systemImage: session.autoScrolling ? "pause.fill" : "arrow.down")
                    .frame(width: 96)
            }.disabled(session.count == 0 || session.state != .capturing)
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.caption).font(BakerTypography.supporting)
                Text("\(session.width) × \(session.height) px")
                    .font(BakerTypography.supporting.monospacedDigit()).foregroundStyle(.secondary)
            }.lineLimit(1).help(session.message).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: session.finish) { Text("Done").frame(width: 44) }
                .buttonStyle(BakerButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                .disabled(session.count == 0 || session.state != .capturing)
        }.padding(10).frame(height: 52).buttonStyle(BakerButtonStyle()).foregroundStyle(BakerTheme.ink)
            .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.border))
    }
}

private struct ScrollCapturePreview: View {
    @ObservedObject var session: ScrollCaptureSession
    var body: some View {
        Group {
            if let image = session.preview {
                Image(nsImage: image).resizable().scaledToFit().padding(6)
                    .accessibilityLabel("Complete scrolling capture overview")
            } else { ProgressView().controlSize(.small) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BakerTheme.border))
    }
}
