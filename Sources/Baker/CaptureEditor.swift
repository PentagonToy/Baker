import AppKit
import BakerCore
import SwiftUI

/// Pixel-coordinate edits are rendered at source resolution, independent of window size.
enum CaptureEditTool: String, CaseIterable {
    case pen = "Pen", rectangle = "Rectangle", ellipse = "Ellipse", arrow = "Arrow", text = "Text", crop = "Crop"
    var symbol: String {
        switch self { case .pen: return "pencil.tip"; case .rectangle: return "rectangle"; case .ellipse: return "circle"; case .arrow: return "arrow.up.right"; case .text: return "textformat"; case .crop: return "crop" }
    }
}
struct CaptureMark {
    let tool: CaptureEditTool
    var points: [CGPoint]
    let colour: NSColor
    let width: CGFloat
    var text = ""
    var filled = false
    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
    func draw() {
        guard let first = points.first, let last = points.last else { return }
        colour.setStroke(); colour.setFill()
        let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        switch tool {
        case .pen: path.move(to: first); for p in points.dropFirst() { path.line(to: p) }
        case .rectangle: path.appendRect(rect)
        case .ellipse: path.appendOval(in: rect)
        case .arrow:
            path.move(to: first); path.line(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x), size = max(12, width * 4)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: last); path.line(to: CGPoint(x: last.x - cos(angle + offset) * size, y: last.y - sin(angle + offset) * size))
            }
        case .text:
            (text as NSString).draw(at: first, withAttributes: [.font: NSFont.systemFont(ofSize: max(18, width * 7), weight: .semibold), .foregroundColor: colour]); return
        case .crop: return
        }
        if filled && (tool == .rectangle || tool == .ellipse) { colour.withAlphaComponent(1).setFill(); path.fill() } else { path.stroke() }
    }
}
@MainActor
final class CaptureEditorState: ObservableObject {
    let image: NSImage
    let pixelSize: NSSize
    @Published var tool = CaptureEditTool.arrow
    @Published var colour = Color.red
    @Published var width: Double = 4
    @Published var filled = false
    @Published var text = ""
    @Published var marks: [CaptureMark] = []
    @Published var saving = false
    @Published var error: String?
    init(image: CGImage) { self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)); pixelSize = self.image.size }
    func rendered() throws -> CGImage {
        guard let context = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BakerError(message: "The edited image could not be rendered.") }
        context.translateBy(x: 0, y: pixelSize.height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let bounds = CGRect(origin: .zero, size: pixelSize)
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        marks.filter { $0.tool != .crop }.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = context.makeImage() else { throw BakerError(message: "The edited image could not be rendered.") }
        guard let crop = marks.last(where: { $0.tool == .crop }) else { return cg }
        let rect = crop.rect.integral.intersection(bounds)
        guard rect.width >= 2, rect.height >= 2, let result = cg.cropping(to: rect) else { throw BakerError(message: "Select a crop at least 2 pixels wide and high.") }
        return result
    }
}
struct CaptureEditorView: View {
    @ObservedObject var state: CaptureEditorState
    let done: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(CaptureEditTool.allCases, id: \.self) { tool in
                    Button { state.tool = tool } label: { Image(systemName: tool.symbol).frame(width: 25, height: 24).background(state.tool == tool ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5)) }.help(tool.rawValue).accessibilityLabel(tool.rawValue)
                }
                Divider().frame(height: 22)
                ColorPicker("Colour", selection: $state.colour).labelsHidden()
                Picker("Width", selection: $state.width) { ForEach([2.0, 4.0, 8.0], id: \.self) { Text("\(Int($0)) px").tag($0) } }.frame(width: 90).labelsHidden()
                if state.tool == .rectangle || state.tool == .ellipse { Toggle("Fill", isOn: $state.filled).toggleStyle(.button).help("Opaque fill covers the pixels beneath the shape") }
                Spacer()
                Button("Undo") { _ = state.marks.popLast() }.disabled(state.marks.isEmpty)
                Button("Reset") { state.marks = [] }.disabled(state.marks.isEmpty)
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(state.saving ? "Saving…" : "Done", action: done).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(12).disabled(state.saving)
            if state.tool == .text { TextField("Text, then click the image", text: $state.text).textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8) }
            CaptureCanvas(state: state).background(BakerTheme.sidebar)
            HStack { Text("\(Int(state.pixelSize.width)) × \(Int(state.pixelSize.height))"); Spacer(); Text(state.error ?? "Done overwrites this capture. Masked pixels and its old OCR result are removed.") }.font(.caption).foregroundStyle(state.error == nil ? .secondary : Color.red).padding(10)
        }.frame(minWidth: 850, minHeight: 500).background(BakerTheme.background)
    }
}
private struct CaptureCanvas: NSViewRepresentable {
    @ObservedObject var state: CaptureEditorState
    func makeNSView(context: Context) -> CaptureCanvasView { CaptureCanvasView(state: state) }
    func updateNSView(_ view: CaptureCanvasView, context: Context) { view.needsDisplay = true }
}
@MainActor
private final class CaptureCanvasView: NSView {
    let state: CaptureEditorState
    private var pending: CaptureMark?
    init(state: CaptureEditorState) { self.state = state; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var scale: CGFloat { max(0.001, min((bounds.width - 40) / state.pixelSize.width, (bounds.height - 40) / state.pixelSize.height)) }
    private var imageRect: CGRect { CGRect(x: (bounds.width - state.pixelSize.width * scale) / 2, y: (bounds.height - state.pixelSize.height * scale) / 2, width: state.pixelSize.width * scale, height: state.pixelSize.height * scale) }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.translateBy(x: imageRect.minX, y: imageRect.minY); context.scaleBy(x: scale, y: scale)
        context.clip(to: CGRect(origin: .zero, size: state.pixelSize))
        state.image.draw(in: CGRect(origin: .zero, size: state.pixelSize), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for mark in state.marks + (pending.map { [$0] } ?? []) {
            if mark.tool == .crop {
                NSColor.white.setStroke(); let path = NSBezierPath(rect: mark.rect); path.lineWidth = 1 / scale; path.setLineDash([5 / scale, 4 / scale], count: 2, phase: 0); path.stroke()
            } else { mark.draw() }
        }
        context.restoreGState()
    }
    private func pixelPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: max(0, min(state.pixelSize.width, (p.x - imageRect.minX) / scale)), y: max(0, min(state.pixelSize.height, (p.y - imageRect.minY) / scale)))
    }
    override func mouseDown(with event: NSEvent) {
        guard !state.saving, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        let p = pixelPoint(event)
        pending = CaptureMark(tool: state.tool, points: [p, p], colour: NSColor(state.colour), width: state.width, text: state.text, filled: state.filled)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard pending != nil else { return }
        if pending?.tool == .pen { pending?.points.append(pixelPoint(event)) }
        else { pending?.points[1] = pixelPoint(event) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let mark = pending else { return }; pending = nil
        if mark.tool == .text ? !mark.text.isEmpty : (mark.rect.width >= 1 || mark.rect.height >= 1) { state.marks.append(mark) }
        needsDisplay = true
    }
}
