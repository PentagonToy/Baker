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
    private var stream: SCStream?
    private var output: RecordingStreamOutput?
    private var writer: RecordingMovieWriter?
    private var stopRequested = false
    private var streamError: Error?
    private let cancellation = RecordingCancellation()
    private var completion: ((Result<URL?, Error>) -> Void)?

    /// On success the caller owns the returned file and its private baker-recording-* parent directory.
    func start(capture: PreparedCapture, region: CaptureRegion, format: RecordingFormat,
               completion: @escaping (Result<URL?, Error>) -> Void) {
        guard state == .idle else {
            completion(.failure(BakerError(message: "This recording session has already been used."))); return
        }
        state = .preparing; self.format = format; self.completion = completion
        showControls(region: region)
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
                let writer = try RecordingMovieWriter(url: movie, width: dimensions.width, height: dimensions.height, format: format)
                self.writer = writer
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = region.rect
                configuration.width = dimensions.width; configuration.height = dimensions.height
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(format.framesPerSecond))
                configuration.queueDepth = 3
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = true
                configuration.capturesAudio = false
                let output = RecordingStreamOutput(writer: writer) { [weak self] error in
                    Task { @MainActor in self?.streamError = error }
                }
                self.output = output
                let stream = SCStream(filter: capture.filter, configuration: configuration, delegate: output)
                self.stream = stream
                try stream.addStreamOutput(output, type: .screen,
                    sampleHandlerQueue: DispatchQueue(label: "baker.recording.frames", qos: .userInitiated))
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
        let callback = completion; completion = nil; task = nil
        callback?(result)
    }

    private func showControls(region: CaptureRegion) {
        let panel = NSPanel(contentRect: CGRect(x: region.screen.frame.minX + 24, y: region.screen.frame.minY + 24, width: 440, height: 138),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Baker · \(format.title) recording"
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RecordingControls(session: self))
        panel.orderFrontRegardless(); self.panel = panel
    }
}

private struct RecordingControls: View {
    @ObservedObject var session: RecordingSession
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.message).font(.callout).lineLimit(2)
            HStack {
                Text("\(Int(session.elapsed)) / \(Int(session.format.maximumDuration))s").monospacedDigit()
                    .font(.caption).foregroundStyle(.secondary)
                if session.droppedFrames > 0 {
                    Text("\(session.droppedFrames) frames skipped").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: session.cancel)
                Button("Stop", action: session.stop).buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(session.state != .recording)
            }
            Text("Silent capture · \(session.format.framesPerSecond) fps · Up to \(session.format.maximumDimension)px")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16).frame(width: 440, height: 138)
    }
}
