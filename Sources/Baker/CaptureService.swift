import BakerCore
import AppKit
import ScreenCaptureKit

enum CaptureSelection {
    static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width >= 2 && rect.height >= 2
    }
}

struct CaptureRegion {
    let screen: NSScreen
    /// Display-local coordinates in points, with a top-left origin.
    let rect: CGRect
}

@MainActor
final class CaptureService {
    private let selector = RegionSelector()
    private var armed = false
    private var captureAccessKnown = false
    private var contentTask: Task<SCShareableContent, Error>?

    func warmSelection() {
        selector.prepare()
        captureAccessKnown = CGPreflightScreenCaptureAccess()
    }
    func cancelSelection() { selector.cancel(); contentTask?.cancel(); contentTask = nil }

    /// Arm the input shield synchronously, before launching any asynchronous work.
    func beginSelection() {
        guard !armed else { return }
        armed = true
        selector.begin()
        if captureAccessKnown {
            contentTask = Task { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        }
    }
    func selectRegion() async -> CaptureRegion? {
        if !armed { beginSelection() }
        defer { armed = false }
        return await selector.result()
    }

    func prepare(_ region: CaptureRegion) async throws -> PreparedCapture {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw BakerError(message: "Allow Baker in System Settings > Privacy & Security > Screen Recording, then try again.")
        }
        captureAccessKnown = true
        let pending = contentTask
        contentTask = nil
        let content: SCShareableContent
        if let pending {
            do { content = try await pending.value }
            catch { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        } else { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        let number = region.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let display = content.displays.first(where: { $0.displayID == number?.uint32Value }) else {
            throw BakerError(message: "The selected display is no longer available.")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.rect
        configuration.width = Int((region.rect.width * region.screen.backingScaleFactor).rounded())
        configuration.height = Int((region.rect.height * region.screen.backingScaleFactor).rounded())
        guard configuration.width >= 2, configuration.height >= 2,
              configuration.width <= 8192, configuration.height <= 8192,
              configuration.width <= ScrollStitcher.pixelLimit / configuration.height else {
            throw BakerError(message: "Choose a region between 2 × 2px and 32 megapixels, with each side no larger than 8192px.")
        }
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return PreparedCapture(filter: filter, configuration: configuration)
    }
}

struct PreparedCapture {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration

    func image() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

@MainActor
private final class RegionSelector {
    private var windows: [NSWindow] = []
    private var screenSignature = ""
    private var continuation: CheckedContinuation<CaptureRegion?, Never>?
    private var resolved = false
    private var active = false
    private var selectedRegion: CaptureRegion?
    private var cursorPushed = false

    func prepare() {
        let screens = NSScreen.screens
        let signature = screens.map { "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? ""):\($0.frame):\($0.backingScaleFactor)" }.joined(separator: ";")
        guard windows.isEmpty || signature != screenSignature else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = []; screenSignature = signature
        for screen in screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: true)
            window.level = .screenSaver; window.sharingType = .none
            window.isOpaque = false; window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.completion = { [weak self] rect in
                guard let rect else { self?.complete(nil); return }
                self?.complete(CaptureRegion(screen: screen, rect: CGRect(x: rect.minX,
                    y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)))
            }
            window.contentView = view
            windows.append(window)
        }
    }
    func begin() {
        prepare()
        resolved = false; selectedRegion = nil; active = true
        windows.forEach {
            ($0.contentView as? SelectionView)?.resetSelection()
            $0.orderFrontRegardless()
        }
        let window = windows.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? windows.first
        window?.makeKey(); window?.makeFirstResponder(window?.contentView)
        if !cursorPushed { NSCursor.crosshair.push(); cursorPushed = true }
        NSApp.activate(ignoringOtherApps: true)
        window?.displayIfNeeded()
    }
    func result() async -> CaptureRegion? {
        if resolved { return selectedRegion }
        return await withCheckedContinuation { continuation = $0 }
    }
    func cancel() { if active { complete(nil) } }
    private func complete(_ region: CaptureRegion?) {
        guard active else { return }
        active = false; resolved = true; selectedRegion = region
        windows.forEach { $0.orderOut(nil) }
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        let waiting = continuation; continuation = nil
        waiting?.resume(returning: region)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var completion: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    private var invalidSelection = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func resetSelection() { start = nil; selection = nil; invalidSelection = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) { invalidSelection = false; start = convert(event.locationInWindow, from: nil); selection = nil; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(start.x - point.x), height: abs(start.y - point.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let start {
            let point = convert(event.locationInWindow, from: nil)
            selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                width: abs(start.x - point.x), height: abs(start.y - point.y)).intersection(bounds)
        }
        guard let selection, CaptureSelection.isValid(selection) else {
            start = nil; selection = nil; invalidSelection = true; needsDisplay = true
            return
        }
        completion?(selection)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { completion?(nil) } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.24).setFill(); shade.fill()
        if let selection {
            let dimensions = "\(Int(selection.width.rounded())) × \(Int(selection.height.rounded())) pt"
            let labelAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.75)]
            let size = dimensions.size(withAttributes: labelAttributes)
            dimensions.draw(at: CGPoint(x: min(max(8, selection.minX), bounds.width - size.width - 8), y: max(8, selection.minY - size.height - 8)), withAttributes: labelAttributes)
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let outline = NSBezierPath(rect: selection); outline.lineWidth = 1; outline.stroke()
        }
        if invalidSelection {
            let message = "Drag to select · Esc to cancel"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.65)]
            let size = message.size(withAttributes: attributes)
            message.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: 32), withAttributes: attributes)
        }
    }
}
