import BakerCore
import AppKit
import ScreenCaptureKit
import SwiftUI

enum CaptureSelection {
    static func pixelScale(filter: CGFloat, screen: CGFloat) -> CGFloat { max(filter, screen) }
    static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width >= 2 && rect.height >= 2
    }
    static let resizeAnchors = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0),
        CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5),
        CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 1), CGPoint(x: 1, y: 1)
    ]
    static func cursor(handle: Int, flipped: Bool = false) -> NSCursor {
        let positions: [NSCursor.FrameResizePosition] = flipped
            ? [.topLeft, .top, .topRight, .left, .right, .bottomLeft, .bottom, .bottomRight]
            : [.bottomLeft, .bottom, .bottomRight, .left, .right, .topLeft, .top, .topRight]
        return .frameResize(position: positions[handle], directions: .all)
    }
    static func adjusted(_ rect: CGRect, delta: CGPoint, handle: Int?, within bounds: CGRect) -> CGRect {
        guard let handle else {
            return CGRect(x: min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width),
                y: min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height), width: rect.width, height: rect.height)
        }
        let anchor = resizeAnchors[handle]
        let left = anchor.x == 0 ? max(bounds.minX, min(rect.maxX - 2, rect.minX + delta.x)) : rect.minX
        let right = anchor.x == 1 ? min(bounds.maxX, max(rect.minX + 2, rect.maxX + delta.x)) : rect.maxX
        let bottom = anchor.y == 0 ? max(bounds.minY, min(rect.maxY - 2, rect.minY + delta.y)) : rect.minY
        let top = anchor.y == 1 ? min(bounds.maxY, max(rect.minY + 2, rect.maxY + delta.y)) : rect.maxY
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
    static func draw(_ rect: CGRect, scale: CGFloat = 1) {
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: rect); border.lineWidth = 1 / scale; border.stroke()
        let grid = NSBezierPath(); grid.lineWidth = 1 / scale
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            let x = rect.minX + rect.width * fraction, y = rect.minY + rect.height * fraction
            grid.move(to: CGPoint(x: x, y: rect.minY)); grid.line(to: CGPoint(x: x, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: y)); grid.line(to: CGPoint(x: rect.maxX, y: y))
        }
        NSColor.white.withAlphaComponent(0.45).setStroke(); grid.stroke()
        NSColor.white.setStroke()
        for anchor in resizeAnchors {
            let center = CGPoint(x: rect.minX + anchor.x * rect.width, y: rect.minY + anchor.y * rect.height)
            let handle = NSBezierPath(); handle.lineWidth = 4 / scale; handle.lineCapStyle = .round
            if anchor.x == 0.5 {
                handle.move(to: CGPoint(x: center.x - 6 / scale, y: center.y)); handle.line(to: CGPoint(x: center.x + 6 / scale, y: center.y))
            } else if anchor.y == 0.5 {
                handle.move(to: CGPoint(x: center.x, y: center.y - 6 / scale)); handle.line(to: CGPoint(x: center.x, y: center.y + 6 / scale))
            } else {
                handle.move(to: CGPoint(x: center.x, y: center.y + (anchor.y == 0 ? 10 : -10) / scale))
                handle.line(to: center); handle.line(to: CGPoint(x: center.x + (anchor.x == 0 ? 10 : -10) / scale, y: center.y))
            }
            handle.stroke()
        }
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
    private let windowSelector = CaptureWindowSelector()
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

    static func application(in region: CaptureRegion) -> NSRunningApplication? {
        let top = NSScreen.screens.first?.frame.maxY ?? region.screen.frame.maxY
        let point = CGPoint(x: region.screen.frame.minX + region.rect.midX, y: top - region.screen.frame.maxY + region.rect.midY)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point) else { continue }
            return NSRunningApplication(processIdentifier: pid)
        }
        return nil
    }

    func warmSelection() {
        selector.prepare()
        captureAccessKnown = CGPreflightScreenCaptureAccess()
    }
    func cancelSelection() { selector.cancel(); windowSelector.cancel(); contentTask?.cancel(); contentTask = nil; frozenTask?.cancel(); frozenTask = nil; frozenScreen = nil }

    /// Arm the input shield synchronously, before launching any asynchronous work.
    func beginSelection(freeze: Bool = true, hideDesktopIcons: Bool = false, confirmsSelection: Bool = false) {
        guard !armed else { return }
        armed = true
        selector.begin(confirmsSelection: confirmsSelection)
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

    func captureWindow() async throws -> CapturedFrame? {
        guard let source = try await prepareWindow() else { return nil }
        let image = try await source.capture.image()
        try Task.checkCancellation()
        return CapturedFrame(image: image, region: source.region)
    }
    func prepareWindow() async throws -> PreparedWindowCapture? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw BakerError(message: "Allow Baker in System Settings → Privacy & Security → Screen Recording.", code: .permissionDenied)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let window = await windowSelector.choose(content.windows) else { return nil }
        try Task.checkCancellation()
        // Resolve again after the picker closes; window IDs may disappear during selection.
        let current = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let selected = current.windows.first(where: { $0.windowID == window.windowID }),
              let screen = NSScreen.screens.max(by: { Self.overlap($0, selected.frame) < Self.overlap($1, selected.frame) }) else {
            throw BakerError(message: "The selected window is no longer available.", code: .captureFailed)
        }
        let filter = SCContentFilter(desktopIndependentWindow: selected)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let width = (filter.contentRect.width * scale).rounded()
        let height = (filter.contentRect.height * scale).rounded()
        guard width.isFinite, height.isFinite, (2...8192).contains(width), (2...8192).contains(height) else {
            throw BakerError(message: "The window exceeds the capture size limit.", code: .invalidInput)
        }
        configuration.width = Int(width)
        configuration.height = Int(height)
        guard configuration.width >= 2, configuration.height >= 2,
              configuration.width <= 8192, configuration.height <= 8192,
              configuration.width <= ScrollStitcher.pixelLimit / configuration.height else {
            throw BakerError(message: "The window exceeds the capture size limit.", code: .invalidInput)
        }
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let frame = selected.frame
        let local = CGRect(x: frame.minX - screen.frame.minX, y: frame.minY - (top - screen.frame.maxY), width: frame.width, height: frame.height)
        return PreparedWindowCapture(capture: PreparedCapture(filter: filter, configuration: configuration),
            region: CaptureRegion(screen: screen, rect: local), application: selected.owningApplication.flatMap { NSRunningApplication(processIdentifier: $0.processID) },
            frame: selected.frame, title: selected.title ?? "")
    }
    private static func overlap(_ screen: NSScreen, _ rect: CGRect) -> CGFloat {
        let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let global = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let overlap = global.intersection(rect)
        return overlap.isNull ? 0 : overlap.width * overlap.height
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
            throw BakerError(message: "Allow Baker in System Settings > Privacy & Security > Screen Recording, then try again.", code: .permissionDenied)
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
            throw BakerError(message: "The selected display is no longer available.", code: .captureFailed)
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
        let scale = CaptureSelection.pixelScale(filter: CGFloat(filter.pointPixelScale), screen: region.screen.backingScaleFactor)
        configuration.width = Int((region.rect.width * scale).rounded())
        configuration.height = Int((region.rect.height * scale).rounded())
        guard configuration.width >= 2, configuration.height >= 2,
              configuration.width <= 8192, configuration.height <= 8192,
              configuration.width <= ScrollStitcher.pixelLimit / configuration.height else {
            throw BakerError(message: "Choose a region between 2 × 2px and 32 megapixels, with each side no larger than 8192px.", code: .invalidInput)
        }
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return PreparedCapture(filter: filter, configuration: configuration)
    }
}

struct PreparedWindowCapture {
    let capture: PreparedCapture
    let region: CaptureRegion
    let application: NSRunningApplication?
    let frame: CGRect
    let title: String
}

struct PreparedCapture {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration

    func preview() async throws -> CGImage {
        let config = SCStreamConfiguration()
        let scale = min(640 / Double(configuration.width), 400 / Double(configuration.height))
        config.width = max(2, Int(Double(configuration.width) * scale)); config.height = max(2, Int(Double(configuration.height) * scale))
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    func image() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}

@MainActor
private final class RegionSelector {
    private var windows: [SelectionWindow] = []
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
            let contentRect = CGRect(origin: .zero, size: screen.frame.size)
            let window = SelectionWindow(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: true, screen: screen)
            window.targetScreen = screen
            window.level = .screenSaver; window.sharingType = .none
            window.hidesOnDeactivate = false
            window.isOpaque = false; window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: contentRect)
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
        for window in windows where window.targetScreen == screen {
            (window.contentView as? SelectionView)?.snapshot = NSImage(cgImage: image, size: screen.frame.size)
            window.contentView?.needsDisplay = true
        }
    }
    func begin(confirmsSelection: Bool = false) {
        prepare()
        resolved = false; selectedRegion = nil; active = true
        for window in windows {
            // Keep the cached panel aligned to the full display, including portrait displays.
            if let screen = window.targetScreen, window.frame != screen.frame {
                window.setFrame(screen.frame, display: false)
            }
            if let view = window.contentView as? SelectionView {
                view.confirmsSelection = confirmsSelection
                view.resetSelection()
            }
            window.orderFrontRegardless()
            window.displayIfNeeded()
        }
        let window = windows.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? windows.first
        window?.makeKey(); window?.makeFirstResponder(window?.contentView)
        if !cursorPushed { NSCursor.crosshair.push(); cursorPushed = true }
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
    var targetScreen: NSScreen?
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var completion: ((CGRect?) -> Void)?
    var snapshot: NSImage?
    private var start: CGPoint?
    private var selection: CGRect?
    private var invalidSelection = false
    var confirmsSelection = false
    private var originalSelection: CGRect?
    private var resizeHandle: Int?
    private var controls: NSView?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func resetSelection() {
        snapshot = nil; start = nil; selection = nil; originalSelection = nil
        resizeHandle = nil; invalidSelection = false
        setAccessibilityLabel(nil); setAccessibilityElement(false)
        controls?.removeFromSuperview(); controls = nil; needsDisplay = true
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard confirmsSelection, let selection else { return }
        addCursorRect(selection.insetBy(dx: 12, dy: 12), cursor: .openHand)
        for (index, anchor) in CaptureSelection.resizeAnchors.enumerated() {
            let center = CGPoint(x: selection.minX + anchor.x * selection.width, y: selection.minY + anchor.y * selection.height)
            addCursorRect(CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24), cursor: CaptureSelection.cursor(handle: index))
        }
        if let controls, !controls.isHidden { addCursorRect(controls.frame, cursor: .arrow) }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        invalidSelection = false
        let point = convert(event.locationInWindow, from: nil)
        start = point; originalSelection = nil; resizeHandle = nil
        if confirmsSelection, let selection {
            resizeHandle = CaptureSelection.resizeAnchors.firstIndex {
                let center = CGPoint(x: selection.minX + $0.x * selection.width, y: selection.minY + $0.y * selection.height)
                return CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24).contains(point)
            }
            if resizeHandle != nil || selection.contains(point) { originalSelection = selection }
        }
        if originalSelection == nil { selection = nil; controls?.isHidden = true }
        else { controls?.isHidden = true; if resizeHandle == nil { NSCursor.closedHand.set() } }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let originalSelection {
            selection = CaptureSelection.adjusted(originalSelection, delta: CGPoint(x: point.x - start.x, y: point.y - start.y), handle: resizeHandle, within: bounds)
        } else {
            selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                width: abs(start.x - point.x), height: abs(start.y - point.y)).intersection(bounds)
        }
        if let selection {
            setAccessibilityElement(true); setAccessibilityRole(.group)
            setAccessibilityLabel("Selected area \(Int(selection.width.rounded())) × \(Int(selection.height.rounded())) points")
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selection, CaptureSelection.isValid(selection) else {
            start = nil; selection = nil; invalidSelection = true; needsDisplay = true
            controls?.isHidden = true
            return
        }
        start = nil; originalSelection = nil
        if confirmsSelection { placeControls(); window?.invalidateCursorRects(for: self); needsDisplay = true }
        else { completion?(selection) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { completion?(nil) }
        else if confirmsSelection && (event.keyCode == 36 || event.keyCode == 76) { confirmSelection() }
        else if confirmsSelection, let selection, [123, 124, 125, 126].contains(event.keyCode) {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta = CGPoint(x: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,
                y: event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0)
            self.selection = CaptureSelection.adjusted(selection, delta: delta, handle: nil, within: bounds)
            placeControls(); window?.invalidateCursorRects(for: self); needsDisplay = true
        }
        else { super.keyDown(with: event) }
    }
    @objc private func confirmSelection() {
        guard let selection, CaptureSelection.isValid(selection) else { return }
        completion?(selection)
    }
    @objc private func cancelSelection() { completion?(nil) }
    private func placeControls() {
        guard let selection, CaptureSelection.isValid(selection) else { return }
        if controls == nil {
            let view = NSHostingView(rootView: ScrollSelectionControls(cancel: { [weak self] in self?.cancelSelection() }, start: { [weak self] in self?.confirmSelection() }))
            addSubview(view); controls = view
        }
        let width: CGFloat = 228, height: CGFloat = 48
        let y = selection.minY >= height + 20 ? selection.minY - height - 12
            : min(bounds.maxY - height - 8, selection.maxY + 12)
        controls?.frame = CGRect(x: min(max(bounds.minX + 8, selection.midX - width / 2), bounds.maxX - width - 8),
            y: max(bounds.minY + 8, y), width: width, height: height)
        controls?.isHidden = false
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
            dimensions.draw(at: CGPoint(x: min(max(8, selection.minX), bounds.width - size.width - 8), y: min(bounds.height - size.height - 8, selection.maxY + 8)), withAttributes: labelAttributes)
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let outline = NSBezierPath(rect: selection); outline.lineWidth = 1; outline.stroke()
            if confirmsSelection { CaptureSelection.draw(selection) }
        }
        if start == nil && selection == nil {
            let message = invalidSelection ? "Drag a larger area · Esc to cancel"
                : confirmsSelection ? "Select the scrolling content · Esc to cancel" : "Drag to capture · Esc to cancel"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white]
            let size = message.size(withAttributes: attributes)
            let box = CGRect(x: (bounds.width - size.width) / 2 - 24, y: (bounds.height - size.height) / 2 - 16, width: size.width + 48, height: size.height + 32)
            NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.18, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
            message.draw(at: CGPoint(x: box.minX + 24, y: box.minY + 16), withAttributes: attributes)
        }
    }
}

struct ScrollSelectionControls: View {
    let cancel: () -> Void
    let start: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: cancel) { Image(systemName: "xmark").frame(width: 16) }
                .help("Cancel capture").accessibilityLabel("Cancel capture").keyboardShortcut(.cancelAction)
            Button(action: start) { Text("Start Capture").frame(maxWidth: .infinity) }
                .buttonStyle(BakerButtonStyle(prominent: true, expands: true)).keyboardShortcut(.defaultAction)
        }.padding(8).buttonStyle(BakerButtonStyle()).foregroundStyle(BakerTheme.ink)
            .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.border))
    }
}
