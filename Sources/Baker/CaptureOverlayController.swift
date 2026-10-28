import AppKit
import BakerCore
import SwiftUI
import Combine
import ImageIO
import QuartzCore

enum CaptureStackLayout {
    static func capacity(heights: [CGFloat], availableHeight: CGFloat, limit: Int) -> Int {
        var used: CGFloat = 0, count = 0
        for height in heights.prefix(limit > 0 ? limit : heights.count) {
            let next = used + (count == 0 ? 0 : 12) + height
            guard next <= availableHeight else { break }
            used = next; count += 1
        }
        return count
    }
}

@MainActor
final class CaptureOverlayController {
    private let model: Workbench
    private var cards: [(id: UUID, panel: NSPanel)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var visible = true
    private var screen: NSScreen?
    private var retiring: [NSPanel] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let previewWidth: CGFloat = 268
    private var previewHeight: CGFloat { previewWidth / ((1 + sqrt(5)) / 2) }
    private var editors: [UUID: CaptureEditWindow] = [:]
    private var discarding = Set<UUID>()

    init(model: Workbench) {
        self.model = model
        model.$captures.sink { [weak self] records in
            let ids = Set(records.map(\.id))
            DispatchQueue.main.async {
                guard let self else { return }
                for card in self.cards where !ids.contains(card.id) { self.dismiss(card.id) }
            }
        }.store(in: &subscriptions)
        model.$visibleCaptures.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &subscriptions)
        model.$formulaResults.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
    }
    private func updatePointerMonitoring() {
        guard visible && !cards.isEmpty else {
            if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
            if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
            globalMouseMonitor = nil; localMouseMonitor = nil
            return
        }
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            Task { @MainActor in self?.followPointer() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            self?.followPointer(); return event
        }
    }
    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }
    var hasOpenEditors: Bool { !editors.isEmpty }
    func resetStorage() {
        cards.forEach { $0.panel.close() }; cards = []
        retiring.forEach { $0.close() }; retiring = []; screen = nil
        updatePointerMonitoring()
    }
    func show(_ record: CaptureRecord) {
        Task { await present(record) }
    }
    private func present(_ record: CaptureRecord, replacing: UUID? = nil) async {
        do {
            let thumbnail = try await model.thumbnail(record)
            guard model.captures.contains(where: { $0.id == record.id }) else { return }
            let slot = replacing.flatMap { id in cards.firstIndex { $0.id == id } } ?? 0
            if let replacing { dismiss(replacing) }
            if let index = cards.firstIndex(where: { $0.id == record.id }) { cards.remove(at: index).panel.close() }
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: previewWidth, height: previewHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = CaptureHostingView(rootView: CaptureCardView(model: model, record: record, thumbnail: thumbnail, edit: { [weak self] in self?.edit(record) }, dismiss: { [weak self] in self?.dismiss(record.id) }, discard: { [weak self] in self?.discard(record) }))
            if replacing == nil { screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main }
            cards.insert((record.id, panel), at: min(slot, cards.count))
            panel.alphaValue = 0
            if let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                let y = cards.prefix(slot).reduce(frame.minY + 20) { $0 + cardHeight($1.id) + 12 }
                panel.setFrame(CGRect(x: frame.minX + 20, y: y - 8, width: previewWidth, height: cardHeight(record.id)), display: false)
            }
            layout()
            if visible { panel.orderFrontRegardless() }
            await NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25; panel.animator().alphaValue = 1 }
        } catch { model.report(error, fallback: .storageFailed) }
    }
    func edit(_ record: CaptureRecord) {
        guard !model.busy else { return }
        if let editor = editors[record.id] { editor.makeKeyAndOrderFront(nil); return }
        do {
            let url = model.captureURL(record)
            let image: CGImage
            if record.isVector {
                // Rasterise in memory; Cancel leaves the SVG file untouched.
                let vector = try CaptureSVG(data: Data(contentsOf: url))
                image = try vector.raster(maximumPixelSize: max(vector.width, vector.height))
            } else {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let pixels = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw BakerError(message: "The capture could not be opened for editing.", code: .storageFailed)
                }
                image = pixels
            }
            let state = CaptureEditorState(image: image)
            let editor = CaptureEditWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            editor.isReleasedWhenClosed = false; editor.title = "Baker · Edit Capture"; editor.contentMinSize = NSSize(width: 850, height: 500)
            editor.onClose = { [weak self] in
                state.cancelProcessing()
                guard let self else { return }
                self.editors.removeValue(forKey: record.id)
                if self.visible { self.cards.first { $0.id == record.id }?.panel.orderFrontRegardless() }
            }
            editor.contentView = CaptureHostingView(rootView: CaptureEditorView(state: state, done: { [weak self, weak editor] in
                guard let self, !state.saving, !state.processing else { return }
                state.saving = true; state.error = nil; editor?.standardWindowButton(.closeButton)?.isEnabled = false
                Task {
                    do {
                        let image = try state.rendered()
                        let updated = try await self.model.saveEditedCapture(image, vector: state.vector, replacing: record)
                        editor?.onClose = nil; self.editors.removeValue(forKey: record.id); editor?.close()
                        await self.present(updated, replacing: record.id)
                    } catch { state.error = error.localizedDescription; state.saving = false; editor?.standardWindowButton(.closeButton)?.isEnabled = true }
                }
            }, cancel: { [weak editor] in editor?.close() }))
            editors[record.id] = editor
            cards.first { $0.id == record.id }?.panel.orderOut(nil)
            editor.center(); editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        } catch { model.report(error, fallback: .storageFailed) }
    }
    func dismiss(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        retire(cards.remove(at: index).panel, upwards: false); layout()
    }
    private func discard(_ record: CaptureRecord) {
        guard discarding.insert(record.id).inserted else { return }
        Task {
            defer { discarding.remove(record.id) }
            if await model.discardCapture(record) { dismiss(record.id) }
        }
    }
    private func retire(_ panel: NSPanel, upwards: Bool) {
        retiring.append(panel)
        panel.ignoresMouseEvents = true
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0 : 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            if !reduced { panel.animator().setFrame(panel.frame.offsetBy(dx: upwards ? 0 : -14, dy: upwards ? 48 : 6), display: true) }
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.close()
                self?.retiring.removeAll { $0 === panel }
            }
        }
    }
    func setVisible(_ value: Bool) {
        visible = value
        updatePointerMonitoring()
        if !value { retiring.forEach { $0.close() }; retiring = [] }
        cards.forEach { if value && editors[$0.id] == nil { $0.panel.orderFrontRegardless() } else { $0.panel.orderOut(nil) } }
    }
    private func followPointer() {
        guard visible, !cards.isEmpty, NSEvent.pressedMouseButtons == 0,
              let target = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), target != screen else { return }
        screen = target; layout(screenTransition: true)
    }
    private func cardHeight(_ id: UUID) -> CGFloat {
        model.formulaResults[id] == nil ? previewHeight : FormulaCardLayout.size.height
    }
    private func layout(screenTransition: Bool = false) {
        updatePointerMonitoring()
        guard let frame = (screen.flatMap { candidate in NSScreen.screens.first { $0 == candidate } } ?? NSScreen.main)?.visibleFrame else { return }
        let capacity = CaptureStackLayout.capacity(heights: cards.map { cardHeight($0.id) }, availableHeight: frame.height - 40, limit: model.visibleCaptures)
        while cards.count > max(1, capacity) { retire(cards.removeLast().panel, upwards: true) }
        NSAnimationContext.runAnimationGroup { context in
            // Longer travel between displays needs more time than rearranging a stack.
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (screenTransition ? 0.45 : 0.3)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            var y = frame.minY + 20
            for card in cards {
                let formula = model.formulaResults[card.id] != nil
                let height = cardHeight(card.id)
                let width: CGFloat = formula ? FormulaCardLayout.size.width : previewWidth
                card.panel.animator().setFrame(CGRect(x: frame.minX + 20, y: y, width: min(width, frame.width - 40), height: height), display: true)
                y += height + 12
            }
        }
    }
}

@MainActor
final class CaptureCardState: ObservableObject {
    @Published var hovering = false
    @Published var copied = false
    @Published var copying = false
}

@MainActor
final class CaptureHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CaptureCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let thumbnail: NSImage
    let edit: () -> Void
    let dismiss: () -> Void
    let discard: () -> Void
    @ObservedObject var state = CaptureCardState()
    var body: some View {
        if let result = model.formulaResults[record.id] {
            FormulaResultCard(model: model, record: record, result: result, discard: discard)
        } else { imageCard }
    }
    private var imageCard: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            CaptureDragView(image: thumbnail, file: model.captureURL(record), edit: edit, completed: dismiss).padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if state.hovering {
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                HStack(spacing: 3) {
                    action(state.copying ? "Copying…" : state.copied ? "Copied" : "Copy", symbol: state.copying ? "hourglass" : state.copied ? "checkmark" : "doc.on.doc") {
                        state.copying = true
                        Task { state.copied = await model.copyCapture(record); state.copying = false }
                    }.disabled(state.copying)
                    action("Save", symbol: "square.and.arrow.down") { Task { if await model.confirmCaptureSaved(record) { dismiss() } } }
                    action("Edit", symbol: "pencil") { edit() }
                    action("Pin", symbol: "pin") { model.selectCapture(record, action: .image) }.disabled(model.busy)
                    Divider().frame(height: 18).overlay(.white.opacity(0.3))
                    action("Read Text", symbol: "text.viewfinder") { model.selectCapture(record, action: .text) }.disabled(model.busy || record.isVector)
                    action("Recognise Formula", symbol: "sum") { model.selectCapture(record, action: .formula) }.disabled(model.busy || record.isVector)
                }.buttonStyle(.plain).foregroundStyle(.white).padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state.hovering {
                Button(action: discard) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).padding(7).background(.ultraThinMaterial, in: Circle()) }
                    .buttonStyle(.plain).padding(8).help("Move capture to Trash").accessibilityLabel("Discard capture")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .padding(3).onHover { value in withAnimation(BakerMotion.selection(reduced: reduceMotion)) { state.hovering = value }; if !value { state.copied = false } }
        .contextMenu {
            Button("Copy") { Task { _ = await model.copyCapture(record) } }
            Button("Edit", action: edit)
            Button("Save") { Task { if await model.confirmCaptureSaved(record) { dismiss() } } }
            Button("Save a Copy As…") { model.saveCapture(record) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.captureURL(record)]) }
            Divider()
            Button("Close Preview", action: dismiss)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Saved capture, \(record.pixelWidth) by \(record.pixelHeight)")
    }
    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol).frame(width: 31, height: 30).contentShape(Rectangle()) }
            .help(title).accessibilityLabel(title)
    }
}

@MainActor
private final class CaptureEditWindow: NSWindow {
    var onClose: (() -> Void)?
    override func close() { let callback = onClose; onClose = nil; super.close(); callback?() }
}
