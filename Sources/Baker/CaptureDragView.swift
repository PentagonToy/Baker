import AppKit
import SwiftUI

/// AppKit reports whether the destination accepted the drop; SwiftUI onDrag cannot.
struct CaptureDragView: NSViewRepresentable {
    let image: NSImage
    let file: URL
    let edit: () -> Void
    let completed: () -> Void
    func makeNSView(context: Context) -> CaptureDragImageView { CaptureDragImageView() }
    func updateNSView(_ view: CaptureDragImageView, context: Context) {
        view.image = image; view.file = file; view.edit = edit; view.completed = completed
        view.needsDisplay = true
    }
}
@MainActor
final class CaptureDragImageView: NSView, NSDraggingSource {
    var image: NSImage?
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    var file: URL?
    var edit: (() -> Void)?
    var completed: (() -> Void)?
    private var down: NSEvent?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { down = nil; edit?() } else { down = event }
    }
    override func mouseUp(with event: NSEvent) { down = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let down, let file, let image, FileManager.default.fileExists(atPath: file.path),
              hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return }
        self.down = nil
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        item.setDraggingFrame(CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height), contents: image)
        let session = beginDraggingSession(with: [item], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { finishDrop(operation) }
    func finishDrop(_ operation: NSDragOperation) {
        if !operation.intersection([.copy, .move, .link]).isEmpty { completed?() }
    }
}
