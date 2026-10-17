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
    private var frozenTask: Task<CGImage, Error>?
    private var frozenScreen: NSScreen?

    /// Resolve before any asynchronous work or window changes can move the pointer.
    static func pointerDisplayRegion() -> CaptureRegion? {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return nil }
        return CaptureRegion(screen: screen, rect: CGRect(origin: .zero, size: screen.frame.size))
    }

    func warmSelection() {
        selector.prepare()
        captureAccessKnown = CGPreflightScreenCaptureAccess()
    }
    func cancelSelection() { selector.cancel(); contentTask?.cancel(); contentTask = nil; frozenTask?.cancel(); frozenTask = nil; frozenScreen = nil }

    /// Arm the input shield synchronously, before launching any asynchronous work.
    func beginSelection(freeze: Bool = true, hideDesktopIcons: Bool = false) {
        guard !armed else { return }
        armed = true
        selector.begin()
        captureAccessKnown = captureAccessKnown || CGPreflightScreenCaptureAccess()
        if captureAccessKnown {
            contentTask = Task { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            if freeze, let region = Self.pointerDisplayRegion() {
                frozenScreen = region.screen
                frozenTask = Task {
                    let prepared = try await self.prepare(region, hideDesktopIcons: hideDesktopIcons)
                    let image = try await prepared.image()
                    try Task.checkCancellation()
                    self.selector.setSnapshot(image, screen: region.screen)
                    return image
                }
            }
        }
    }
    func selectRegion() async -> CaptureRegion? {
        if !armed { beginSelection() }
        defer { armed = false }
        let result = await selector.result()
        if result == nil { frozenTask?.cancel(); frozenTask = nil; frozenScreen = nil }
        return result
    }

    func image(_ region: CaptureRegion, hideDesktopIcons: Bool = false) async throws -> CGImage {
        try Task.checkCancellation()
        defer { frozenTask = nil; frozenScreen = nil }
        if region.screen == frozenScreen, let frozenTask {
            do {
                let image = try await frozenTask.value
                try Task.checkCancellation()
                if let cropped = Self.cropSnapshot(image, region: region) { return cropped }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Retry once through the normal screenshot path. */ }
        }
        let prepared = try await prepare(region, hideDesktopIcons: hideDesktopIcons)
        return try await prepared.image()
    }

    static func cropSnapshot(_ image: CGImage, region: CaptureRegion) -> CGImage? {
        let scaleX = CGFloat(image.width) / region.screen.frame.width
        let scaleY = CGFloat(image.height) / region.screen.frame.height
        let box = CGRect(x: region.rect.minX * scaleX, y: region.rect.minY * scaleY,
                         width: region.rect.width * scaleX, height: region.rect.height * scaleY).integral
        return image.cropping(to: box)
    }

    func prepare(_ region: CaptureRegion, hideDesktopIcons: Bool = false) async throws -> PreparedCapture {
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
        let iconWindows = hideDesktopIcons ? content.windows.filter {
            $0.owningApplication?.bundleIdentifier == "com.apple.finder" && $0.windowLayer == CGWindowLevelForKey(.desktopIconWindow)
        } : []
        // Keep ordinary Baker workspaces visible in both the frozen selection and output.
        // Only capture controls/previews are excluded, rather than every Baker window.
        let normalWindowIDs = Set(NSApp.windows.filter { $0.isVisible && $0.level == .normal }.map { UInt32($0.windowNumber) })
        let controls = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier && !normalWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: iconWindows + controls)
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
            let window = SelectionWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            window.level = .screenSaver; window.sharingType = .none
            window.hidesOnDeactivate = false
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
    func setSnapshot(_ image: CGImage, screen: NSScreen) {
        guard active else { return }
        for window in windows where window.frame == screen.frame {
            (window.contentView as? SelectionView)?.snapshot = NSImage(cgImage: image, size: screen.frame.size)
            window.contentView?.needsDisplay = true
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
        windows.forEach { $0.orderOut(nil); ($0.contentView as? SelectionView)?.snapshot = nil }
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        let waiting = continuation; continuation = nil
        waiting?.resume(returning: region)
    }
}

private final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var completion: ((CGRect?) -> Void)?
    var snapshot: NSImage?
    private var start: CGPoint?
    private var selection: CGRect?
    private var invalidSelection = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func resetSelection() { snapshot = nil; start = nil; selection = nil; invalidSelection = false; needsDisplay = true }
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
        snapshot?.draw(in: bounds)
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
        if start == nil {
            let message = invalidSelection ? "Drag a larger area · Esc to cancel" : "Drag to capture · Esc to cancel"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white]
            let size = message.size(withAttributes: attributes)
            let box = CGRect(x: (bounds.width - size.width) / 2 - 24, y: (bounds.height - size.height) / 2 - 16, width: size.width + 48, height: size.height + 32)
            NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.18, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
            message.draw(at: CGPoint(x: box.minX + 24, y: box.minY + 16), withAttributes: attributes)
        }
    }
}
