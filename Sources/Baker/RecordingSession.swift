import AppKit
import AVFoundation
import BakerCore
import ScreenCaptureKit
import SwiftUI

private final class RecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: RecordingMovieWriter
    let failure: @Sendable (Error) -> Void

    init(writer: RecordingMovieWriter, failure: @escaping @Sendable (Error) -> Void) {
        self.writer = writer; self.failure = failure
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio { writer.appendAudio(sampleBuffer); return }
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else { return }
        writer.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { failure(error) }
}

@MainActor
final class RecordingSession: ObservableObject {
    enum State { case idle, preparing, recording, finishing, completed, cancelled, failed }
    @Published private(set) var state: State = .idle
    @Published private(set) var message = "Preparing recording…"
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var droppedFrames = 0
    private(set) var format: RecordingFormat = .video
    private var task: Task<Void, Never>?
    private var panel: NSPanel?
    private var outline: NSPanel?
    private var stream: SCStream?
    private var output: RecordingStreamOutput?
    private var writer: RecordingMovieWriter?
    private var stopRequested = false
    private var streamError: Error?
    private let cancellation = RecordingCancellation()
    private var completion: ((Result<URL?, Error>) -> Void)?

    /// On success the caller owns the returned file and its private baker-recording-* parent directory.
    func start(capture: PreparedCapture, region: CaptureRegion, format: RecordingFormat, showsCursor: Bool = true, capturesAudio: Bool = false,
               completion: @escaping (Result<URL?, Error>) -> Void) {
        guard state == .idle else {
            completion(.failure(BakerError(message: "This recording session has already been used.", code: .invalidState))); return
        }
        guard !cancellation.isCancelled else { completion(.success(nil)); return }
        state = .preparing; self.format = format; self.completion = completion
        if panel == nil { prepareControls(region: region, format: format) }
        task = Task { [self] in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-recording-\(UUID().uuidString)", isDirectory: true)
            var retainedOutput = false
            defer {
                if !retainedOutput { try? FileManager.default.removeItem(at: directory) }
            }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
                let movie = directory.appendingPathComponent("Recording.mp4")
                let dimensions = try format.dimensions(width: capture.configuration.width, height: capture.configuration.height)
                let writer = try RecordingMovieWriter(url: movie, width: dimensions.width, height: dimensions.height, format: format, capturesAudio: capturesAudio)
                self.writer = writer
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = region.rect
                configuration.width = dimensions.width; configuration.height = dimensions.height
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(format.framesPerSecond))
                configuration.queueDepth = 3
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = showsCursor
                configuration.capturesAudio = capturesAudio && format == .video
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000; configuration.channelCount = 2
                let output = RecordingStreamOutput(writer: writer) { [weak self] error in
                    Task { @MainActor in self?.streamError = error }
                }
                self.output = output
                let stream = SCStream(filter: capture.filter, configuration: configuration, delegate: output)
                self.stream = stream
                try stream.addStreamOutput(output, type: .screen,
                    sampleHandlerQueue: DispatchQueue(label: "baker.recording.frames", qos: .userInitiated))
                if configuration.capturesAudio {
                    try stream.addStreamOutput(output, type: .audio,
                        sampleHandlerQueue: DispatchQueue(label: "baker.recording.audio", qos: .userInitiated))
                }
                if cancellation.isCancelled { throw CancellationError() }
                try await stream.startCapture()
                let started = ProcessInfo.processInfo.systemUptime
                state = .recording
                message = "Recording the selected region. Stop when ready."
                while !stopRequested && !cancellation.isCancelled {
                    if let streamError { throw streamError }
                    if let error = writer.failureError { throw error }
                    elapsed = ProcessInfo.processInfo.systemUptime - started
                    droppedFrames = writer.droppedFrames
                    if elapsed >= format.maximumDuration { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                state = .finishing
                message = cancellation.isCancelled ? "Cancelling…" : "Finishing recording…"
                try await stream.stopCapture()
                self.stream = nil; self.output = nil
                if cancellation.isCancelled { throw CancellationError() }
                let finishedMovie = try await writer.finish()
                self.writer = nil
                var result = finishedMovie
                if format == .gif {
                    message = "Creating GIF…"
                    let destination = directory.appendingPathComponent("Recording.gif")
                    let token = cancellation
                    result = try await Task.detached(priority: .userInitiated) {
                        try await RecordingGIFExporter.export(movie: finishedMovie, to: destination, cancellation: token)
                    }.value
                    try? FileManager.default.removeItem(at: movie)
                }
                if cancellation.isCancelled { throw CancellationError() }
                retainedOutput = true
                complete(.success(result), state: .completed)
            } catch {
                if let stream = self.stream { try? await stream.stopCapture() }
                self.stream = nil; self.output = nil
                self.writer?.cancel(); self.writer = nil
                if cancellation.isCancelled || error is CancellationError {
                    complete(.success(nil), state: .cancelled)
                } else { complete(.failure(error), state: .failed) }
            }
        }
    }

    func stop() {
        guard state == .preparing || state == .recording else { return }
        stopRequested = true; message = "Finishing recording…"
    }

    func cancel() {
        if state == .idle { cancellation.cancel(); panel?.orderOut(nil); panel?.contentView = nil; panel = nil; outline?.orderOut(nil); outline = nil; return }
        guard state == .preparing || state == .recording || state == .finishing else { return }
        cancellation.cancel(); stopRequested = true
        writer?.cancel()
        message = "Cancelling…"
    }

    func cancelAndWait() async {
        let running = task
        cancel()
        await running?.value
    }

    private func complete(_ result: Result<URL?, Error>, state: State) {
        self.state = state
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        outline?.orderOut(nil); outline = nil
        let callback = completion; completion = nil; task = nil
        callback?(result)
    }

    func prepareControls(region: CaptureRegion, format: RecordingFormat) {
        guard panel == nil else { return }
        self.format = format
        let rect = RecordingPlacement.selection(region.rect, on: region.screen.frame)
        outline = RecordingSetup.outline(rect)
        let frame = RecordingPlacement.controls(selection: rect, visible: region.screen.visibleFrame, size: CGSize(width: 300, height: 106))
        let panel = RecordingPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        RecordingSetup.style(panel)
        panel.onEscape = { [weak self] in self?.cancel() }
        panel.contentView = NSHostingView(rootView: RecordingControls(session: self))
        panel.alphaValue = 0; panel.orderFrontRegardless(); RecordingSetup.reveal(panel); self.panel = panel
    }
}

private struct RecordingControls: View {
    @ObservedObject var session: RecordingSession
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(session.state == .recording ? Color.red : BakerTheme.accent).frame(width: 8, height: 8)
                Text(session.format.title).font(.headline)
                Text(time).monospacedDigit().font(.headline)
                Spacer()
                Button(action: session.stop) { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderedProminent).font(BakerTypography.body).tint(BakerTheme.accent)
                    .disabled(session.state != .recording).help("Stop recording").accessibilityLabel("Stop recording")
                Button(action: session.cancel) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Discard recording").accessibilityLabel("Discard recording")
            }
            ProgressView(value: min(session.elapsed, session.format.maximumDuration), total: session.format.maximumDuration)
                .font(BakerTypography.body).tint(BakerTheme.accent)
            HStack {
                Text(session.state == .recording ? "Up to \(Int(session.format.maximumDuration)) seconds" : session.message)
                    .lineLimit(1)
                Spacer()
                if session.droppedFrames > 0 { Text("\(session.droppedFrames) skipped") }
            }.font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.padding(16).frame(width: 300, height: 106)
            .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
    }
    private var time: String { String(format: "%02d:%02d", Int(session.elapsed) / 60, Int(session.elapsed) % 60) }
}
