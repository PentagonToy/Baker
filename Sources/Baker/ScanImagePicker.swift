import AppKit

/// Selects from the chosen window's image, never from unrelated windows on the display.
@MainActor final class ScanImagePicker: NSObject, NSWindowDelegate {
    enum Mode { case area, point }
    private var panel: NSWindow?
    private var continuation: CheckedContinuation<CGRect?, Never>?
    func choose(image: CGImage, screen: NSScreen, mode: Mode) async -> CGRect? {
        cancel()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let available = screen.visibleFrame.insetBy(dx: 48, dy: 48)
            let scale = min(min(900, available.width) / CGFloat(image.width), min(700, available.height - 32) / CGFloat(image.height), 1)
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let value = NSWindow(contentRect: CGRect(origin: CGPoint(x: available.midX - size.width / 2, y: available.midY - size.height / 2), size: size),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            value.title = mode == .area ? "Select page area · Esc to cancel" : "Select next-page button · Esc to cancel"
            value.level = .floating; value.isReleasedWhenClosed = false; value.delegate = self
            let view = ScanImageSelection(frame: CGRect(origin: .zero, size: size))
            view.image = image; view.mode = mode
            view.finished = { [weak self] in self?.finish($0) }
            value.contentView = view; panel = value
            NSApp.activate(ignoringOtherApps: true); value.makeKeyAndOrderFront(nil); value.makeFirstResponder(view)
        }
    }
    func cancel() { finish(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
    private func finish(_ result: CGRect?) {
        panel?.delegate = nil; panel?.contentView = nil; panel?.close(); panel = nil
        let callback = continuation; continuation = nil; callback?.resume(returning: result)
    }
}
private final class ScanImageSelection: NSView {
    var image: CGImage?
    var mode: ScanImagePicker.Mode = .area
    var finished: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { finished?(nil) } }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mode == .point { finished?(CGRect(x: point.x / bounds.width, y: point.y / bounds.height, width: 0, height: 0)); return }
        start = point
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard mode == .area, let rect = selection, rect.width >= 4, rect.height >= 4 else { return }
        finished?(CGRect(x: rect.minX / bounds.width, y: rect.minY / bounds.height, width: rect.width / bounds.width, height: rect.height / bounds.height))
    }
    override func draw(_ dirtyRect: NSRect) {
        if let image { NSImage(cgImage: image, size: bounds.size).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        if let selection {
            NSColor.black.withAlphaComponent(0.25).setFill()
            let mask = NSBezierPath(rect: bounds); mask.appendRect(selection); mask.windingRule = .evenOdd; mask.fill()
            NSColor.controlAccentColor.setStroke(); let outline = NSBezierPath(rect: selection); outline.lineWidth = 2; outline.stroke()
        }
    }
}
