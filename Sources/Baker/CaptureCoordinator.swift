import AppKit
import BakerCore

struct CapturedFrame {
    let image: CGImage
    let region: CaptureRegion
}
struct RecordedClip {
    let url: URL
    let format: RecordingFormat
}

/// Owns selection, live capture and recording lifetimes; it does not own app UI state.
@MainActor
final class CaptureCoordinator {
    private let service = CaptureService()
    private let setup: RecordingSetup
    private var task: Task<Void, Never>?
    private var scrolling: ScrollCaptureSession?
    private var recording: RecordingSession?
    init(preferences: BakerPreferences) { setup = RecordingSetup(preferences: preferences) }
    func warmSelection() { service.warmSelection() }

    func capture(region: CaptureRegion?, scrolling scroll: Bool, hideDesktopIcons: Bool,
                 complete: @escaping (Result<CapturedFrame?, Error>) -> Void) {
        guard task == nil, self.scrolling == nil, recording == nil else {
            complete(.failure(BakerError(message: "A screen capture is already running.", code: .invalidState))); return
        }
        let previousApp = NSWorkspace.shared.frontmostApplication
        if region == nil { service.beginSelection(freeze: !scroll, hideDesktopIcons: hideDesktopIcons) }
        task = Task {
            defer { task = nil; service.cancelSelection() }
            guard !Task.isCancelled else { complete(.failure(CancellationError())); return }
            let selected = region == nil ? await service.selectRegion() : region
            guard let selected else { complete(.success(nil)); return }
            do {
                try Task.checkCancellation()
                if scroll {
                    let prepared = try await service.prepare(selected, hideDesktopIcons: hideDesktopIcons)
                    try Task.checkCancellation()
                    let session = ScrollCaptureSession(); scrolling = session
                    session.start(capture: prepared, region: selected, targetApplication: previousApp) { [weak self] result in
                        self?.scrolling = nil
                        complete(result.map { image in image.map { CapturedFrame(image: $0, region: selected) } })
                    }
                } else {
                    let image = try await service.image(selected, hideDesktopIcons: hideDesktopIcons)
                    try Task.checkCancellation()
                    complete(.success(CapturedFrame(image: image, region: selected)))
                }
            } catch { complete(.failure(error)) }
        }
    }

    func record(format: RecordingFormat?, hideDesktopIcons: Bool, started: @escaping () -> Void,
                complete: @escaping (Result<RecordedClip?, Error>) -> Void) {
        guard task == nil, scrolling == nil, recording == nil else {
            complete(.failure(BakerError(message: "A screen capture is already running.", code: .invalidState))); return
        }
        service.beginSelection(freeze: false)
        task = Task {
            defer { task = nil; service.cancelSelection() }
            var selection: (CaptureRegion, RecordingOptions)?
            while !Task.isCancelled {
                guard let region = await service.selectRegion() else { break }
                switch await setup.choose(region: region, preferredFormat: format) {
                case .start(let options): selection = (region, options)
                case .cancel: break
                case .reselect:
                    service.cancelSelection(); service.beginSelection(freeze: false); continue
                }
                break
            }
            guard let (region, options) = selection, !Task.isCancelled else { complete(.success(nil)); return }
            do {
                service.cancelSelection()
                let session = RecordingSession(); recording = session
                session.prepareControls(region: region, format: options.format)
                let prepared = try await service.prepare(region, hideDesktopIcons: hideDesktopIcons)
                try Task.checkCancellation()
                started()
                session.start(capture: prepared, region: region, format: options.format, showsCursor: options.showsCursor,
                              capturesAudio: options.capturesAudio) { [weak self] result in
                    self?.recording = nil
                    complete(result.map { url in url.map { RecordedClip(url: $0, format: options.format) } })
                }
            } catch { recording?.cancel(); recording = nil; complete(.failure(error)) }
        }
    }
    func stopRecording() { recording?.stop() }
    func cancel() { setup.cancel(); task?.cancel(); service.cancelSelection(); scrolling?.cancel(); recording?.cancel() }
    func close() async {
        let task = task, scrolling = scrolling, recording = recording
        cancel()
        await scrolling?.cancelAndWait()
        _ = await task?.result
        await recording?.cancelAndWait()
    }
}
