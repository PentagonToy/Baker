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
    @Published private(set) var image: NSImage
    var pixelSize: NSSize { image.size }
    @Published private(set) var vector: CaptureSVG?
    @Published private(set) var processing = false
    private let original: NSImage
    private struct Snapshot { let image: NSImage; let marks: [CaptureMark]; let vector: CaptureSVG? }
    private var undoStates: [Snapshot] = [], redoStates: [Snapshot] = []
    private var operation: Task<Processed, Error>?
    private var completion: Task<Void, Never>?
    private var generation = UUID()
    private enum Processed { case raster(CGImage), vector(CaptureSVG, CGImage) }
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }
    var canReset: Bool { image !== original || !marks.isEmpty || vector != nil }
    var canDraw: Bool { !saving && !processing && vector == nil }
    var redoMarks: [CaptureMark] { redoStates.compactMap { $0.marks.last } }
    @Published var tool = CaptureEditTool.arrow
    @Published var selectedColour = CaptureColour.vermillion
    @Published var showingPalette = false
    var colour: Color { selectedColour.colour }
    @Published var width: Double = 4
    @Published var filled = false
    @Published var text = ""
    @Published var marks: [CaptureMark] = []
    @Published var saving = false
    @Published var error: String?
    init(image: CGImage) {
        let value = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        self.image = value; original = value
    }
    private var snapshot: Snapshot { Snapshot(image: image, marks: marks, vector: vector) }
    private func restore(_ state: Snapshot) { image = state.image; marks = state.marks; vector = state.vector; error = nil }
    private func checkpoint() {
        undoStates.append(snapshot); redoStates.removeAll()
        // Drawings share their bitmap; cap cheap drawing revisions separately.
        if undoStates.count > 40 { undoStates.removeFirst() }
    }
    private func trimBitmaps() {
        // Retain the reset source and at most two processed bitmaps, including the current one.
        while !undoStates.isEmpty {
            let transformed = (undoStates.map(\.image) + [image]).filter { $0 !== original }
            guard Set(transformed.map(ObjectIdentifier.init)).count > 2 else { break }
            undoStates.removeFirst()
        }
    }
    func add(_ mark: CaptureMark) { guard canDraw else { return }; checkpoint(); marks.append(mark); error = nil }
    func undo() {
        guard !saving, !processing, let previous = undoStates.popLast() else { return }
        redoStates.append(snapshot); restore(previous)
    }
    func redo() {
        guard !saving, !processing, let next = redoStates.popLast() else { return }
        undoStates.append(snapshot); restore(next)
    }
    func reset() {
        guard !saving, !processing else { return }
        undoStates.removeAll(); redoStates.removeAll(); image = original; vector = nil; marks.removeAll(); error = nil
    }
    func cancelProcessing() {
        let token = UUID(); generation = token; operation?.cancel(); completion?.cancel()
        guard let operation else { processing = false; return }
        // Do not start a second native request while the cancelled one is still unwinding.
        completion = Task { [weak self] in
            _ = await operation.result
            guard let self, self.generation == token else { return }
            self.operation = nil; self.completion = nil; self.processing = false
        }
    }
    func removeBackground(_ mode: BackgroundRemovalMode) {
        start { image in .raster(try ImageBackgroundRemoval.remove(image, mode: mode)) }
    }
    func vectorise(_ mode: ImageVectorMode, tools override: ImageVectorTools? = nil) {
        guard let resources = Bundle.main.resourceURL else { return }
        let tools = override ?? ImageVectorTools(python: resources.appendingPathComponent("Runtime/python/bin/python3.12"),
            worker: resources.appendingPathComponent("image_tools_worker.py"), directory: resources.appendingPathComponent("ImageTools"))
        start { image in
            let vector = try CaptureSVG(data: ImageVectoriser.convert(image, mode: mode, tools: tools))
            return .vector(vector, try vector.raster(maximumPixelSize: max(vector.width, vector.height)))
        }
    }
    private func start(_ action: @escaping @Sendable (CGImage) throws -> Processed) {
        guard canDraw else { return }
        do {
            let input = try rendered(), token = UUID(); generation = token; processing = true; error = nil
            let task = Task.detached(priority: .userInitiated) { try action(input) }; operation = task
            completion = Task { [weak self] in
                do {
                    let output = try await task.value
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.checkpoint()
                    switch output {
                    case .raster(let pixels): self.image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height)); self.vector = nil
                    case .vector(let vector, let pixels): self.image = NSImage(data: vector.data) ?? NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height)); self.vector = vector
                    }
                    self.trimBitmaps(); self.marks.removeAll(); self.processing = false; self.operation = nil; self.completion = nil
                } catch {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.error = error is CancellationError ? nil : error.localizedDescription
                    self.processing = false; self.operation = nil; self.completion = nil
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    deinit { operation?.cancel(); completion?.cancel() }
    func mask() { tool = .rectangle; selectedColour = .white; filled = true }
    var isShape: Bool { tool == .rectangle || tool == .ellipse }
    func rendered() throws -> CGImage {
        guard let context = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BakerError(message: "The edited image could not be rendered.", code: .exportFailed) }
        context.translateBy(x: 0, y: pixelSize.height); context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let bounds = CGRect(origin: .zero, size: pixelSize)
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        marks.filter { $0.tool != .crop }.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = context.makeImage() else { throw BakerError(message: "The edited image could not be rendered.", code: .exportFailed) }
        guard let crop = marks.last(where: { $0.tool == .crop }) else { return cg }
        let rect = crop.rect.integral.intersection(bounds)
        guard rect.width >= 2, rect.height >= 2, let result = cg.cropping(to: rect) else { throw BakerError(message: "Select a crop at least 2 pixels wide and high.", code: .invalidInput) }
        return result
    }
}
struct CaptureEditorView: View {
    @ObservedObject var state: CaptureEditorState
    let done: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(CaptureEditTool.allCases, id: \.self) { tool in
                        Button { state.tool = tool } label: {
                            Image(systemName: tool.symbol).frame(width: 30, height: 28)
                                .foregroundStyle(state.tool == tool ? BakerTheme.accent : Color.primary)
                                .background(state.tool == tool ? BakerTheme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).help(tool.rawValue).accessibilityLabel(tool.rawValue)
                    }
                }.padding(3).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 10)).disabled(!state.canDraw)
                Button(action: state.mask) { Label("Mask", systemImage: "rectangle.fill") }
                    .help("White, opaque rectangle for covering content").disabled(!state.canDraw)
                Divider().frame(height: 22)
                Button { state.showingPalette.toggle() } label: {
                    HStack(spacing: 4) {
                        Circle().fill(state.colour).overlay(Circle().strokeBorder(.primary.opacity(0.25))).frame(width: 19, height: 19)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }.frame(height: 24)
                }.buttonStyle(.plain).help("\(state.selectedColour.name) · \(state.selectedColour.rawValue)")
                    .accessibilityLabel("Colour: " + state.selectedColour.name)
                    .popover(isPresented: $state.showingPalette, arrowEdge: .bottom) { CapturePaletteView(state: state) }.disabled(!state.canDraw)
                Picker("Stroke width", selection: $state.width) {
                    ForEach([2.0, 4.0, 8.0], id: \.self) { Text("\(Int($0)) px").tag($0) }
                }.frame(width: 72).labelsHidden().disabled(!state.canDraw || state.tool == .crop)
                Toggle("Fill", isOn: $state.filled).toggleStyle(.button).disabled(!state.canDraw || !state.isShape)
                    .help("Opaque fill covers the pixels beneath a rectangle or ellipse")
                Spacer(minLength: 2)
                Button(action: state.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!state.canUndo).help("Undo").accessibilityLabel("Undo").keyboardShortcut("z")
                Button(action: state.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!state.canRedo).help("Redo").accessibilityLabel("Redo").keyboardShortcut("z", modifiers: [.command, .shift])
                Button(action: state.reset) { Image(systemName: "arrow.counterclockwise") }
                    .disabled(!state.canReset).help("Reset edits").accessibilityLabel("Reset edits")
                Divider().frame(height: 22)
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(state.saving ? "Saving…" : "Done", action: done).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.controlSize(.small).padding(10).disabled(state.saving || state.processing).font(BakerTypography.body).tint(BakerTheme.accent)
            HStack(spacing: 14) {
                Menu {
                    Button("Paper & Slides") { state.removeBackground(.paper) }
                    Button("Photo Cutout") { state.removeBackground(.subject) }
                } label: { Label("Remove Background", systemImage: "person.crop.rectangle") }.disabled(!state.canDraw)
                Menu {
                    Button("Colour") { state.vectorise(.colour) }
                    Button("Black & White") { state.vectorise(.monochrome) }
                } label: { Label("Vectorise", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.disabled(!state.canDraw)
                Spacer()
                if state.processing {
                    ProgressView().controlSize(.small)
                    Text("Processing…").foregroundStyle(.secondary)
                    Button("Cancel", action: state.cancelProcessing)
                } else if state.vector != nil { Text("SVG · Undo to return to the image").foregroundStyle(.secondary) }
            }.font(BakerTypography.body).padding(.horizontal, 12).padding(.bottom, 10).disabled(state.saving)
            if state.tool == .text && state.canDraw { TextField("Text, then click the image", text: $state.text).textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8) }
            CaptureCanvas(state: state).background(BakerTheme.sidebar)
            HStack { Text("\(Int(state.pixelSize.width)) × \(Int(state.pixelSize.height))"); Spacer(); Text(state.error ?? (state.vector == nil ? "Done replaces this capture with the edited PNG." : "Done replaces this capture with SVG only.")) }.font(BakerTypography.supporting).foregroundStyle(state.error == nil ? .secondary : Color.red).padding(10)
        }.frame(minWidth: 850, minHeight: 500).background(BakerTheme.background)
    }
}
private struct CapturePaletteView: View {
    @ObservedObject var state: CaptureEditorState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Okabe–Ito").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 3), spacing: 10) {
                ForEach(CaptureColour.allCases) { colour in
                    Button { state.selectedColour = colour; state.showingPalette = false } label: {
                        Circle().fill(colour.colour).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                            .overlay {
                                if state.selectedColour == colour {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(colour.checkColour)
                                }
                            }.frame(width: 36, height: 36)
                    }.buttonStyle(.plain).help(colour.name + " · " + colour.rawValue)
                        .accessibilityLabel(colour.name + " " + colour.rawValue)
                        .accessibilityAddTraits(state.selectedColour == colour ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.selectedColour.name).font(BakerTypography.supporting)
                Text(state.selectedColour.rawValue).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                Text("White is added for masking.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
        }.padding(16).background(BakerTheme.surface)
    }
}

private struct CaptureCanvas: NSViewRepresentable {
    @ObservedObject var state: CaptureEditorState
    func makeNSView(context: Context) -> CaptureCanvasView { CaptureCanvasView(state: state) }
    func updateNSView(_ view: CaptureCanvasView, context: Context) { view.needsDisplay = true }
}
@MainActor
private final class CaptureCanvasView: NSView, NSUserInterfaceValidations {
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
        // A neutral checkerboard makes transparent pixels visible without changing the saved image.
        let tile = 12 / scale
        for row in 0...Int(ceil(state.pixelSize.height / tile)) {
            for column in 0...Int(ceil(state.pixelSize.width / tile)) {
                (row + column).isMultiple(of: 2) ? NSColor(white: 0.78, alpha: 1).setFill() : NSColor(white: 0.9, alpha: 1).setFill()
                NSRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
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
    @objc func undo(_ sender: Any?) { if !state.saving && !state.processing { state.undo() } }
    @objc func redo(_ sender: Any?) { if !state.saving && !state.processing { state.redo() } }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return !state.saving && !state.processing && state.canUndo }
        if item.action == #selector(redo(_:)) { return !state.saving && !state.processing && state.canRedo }
        return true
    }
    override func mouseDown(with event: NSEvent) {
        guard state.canDraw, imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
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
        if mark.tool == .text ? !mark.text.isEmpty : (mark.rect.width >= 1 || mark.rect.height >= 1) { state.add(mark) }
        needsDisplay = true
    }
}
