import AppKit
import BakerCore
import SwiftUI
import Combine
import ImageIO
import QuartzCore

@MainActor
final class CaptureOverlayController {
    private let model: Workbench
    private var cards: [(id: UUID, panel: NSPanel)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var visible = true
    private var screen: NSScreen?
    private var retiring: [NSPanel] = []
    private var editors: [UUID: CaptureEditWindow] = [:]

    init(model: Workbench) {
        self.model = model
        model.$visibleCaptures.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &subscriptions)
        model.$formulaResults.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }.store(in: &subscriptions)
    }
    func show(_ record: CaptureRecord) {
        Task { await present(record) }
    }
    private func present(_ record: CaptureRecord, replacing: UUID? = nil) async {
        do {
            let thumbnail = try await model.thumbnail(record)
            let slot = replacing.flatMap { id in cards.firstIndex { $0.id == id } } ?? 0
            if let replacing { dismiss(replacing) }
            if let index = cards.firstIndex(where: { $0.id == record.id }) { cards.remove(at: index).panel.close() }
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 268, height: 184), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = CaptureHostingView(rootView: CaptureCardView(model: model, record: record, thumbnail: thumbnail, edit: { [weak self] in self?.edit(record) }, dismiss: { [weak self] in self?.dismiss(record.id) }))
            if replacing == nil { screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main }
            cards.insert((record.id, panel), at: min(slot, cards.count))
            panel.alphaValue = 0
            if let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                let y = cards.prefix(slot).reduce(frame.minY + 20) { $0 + cardHeight($1.id) + 12 }
                panel.setFrame(CGRect(x: frame.minX + 20, y: y - 8, width: 268, height: cardHeight(record.id)), display: false)
            }
            layout()
            if visible { panel.orderFrontRegardless() }
            await NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25; panel.animator().alphaValue = 1 }
        } catch { model.problem = error.localizedDescription }
    }
    func edit(_ record: CaptureRecord) {
        guard !model.busy else { return }
        if let editor = editors[record.id] { editor.makeKeyAndOrderFront(nil); return }
        do {
            let url = model.captureURL(record)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw BakerError(message: "The capture could not be opened for editing.")
            }
            let state = CaptureEditorState(image: image)
            let editor = CaptureEditWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            editor.isReleasedWhenClosed = false; editor.title = "Baker · Edit Capture"; editor.contentMinSize = NSSize(width: 850, height: 500)
            editor.onClose = { [weak self] in
                guard let self else { return }
                self.editors.removeValue(forKey: record.id)
                if self.visible { self.cards.first { $0.id == record.id }?.panel.orderFrontRegardless() }
            }
            editor.contentView = CaptureHostingView(rootView: CaptureEditorView(state: state, done: { [weak self, weak editor] in
                guard let self, !state.saving else { return }
                state.saving = true; state.error = nil; editor?.standardWindowButton(.closeButton)?.isEnabled = false
                Task {
                    do {
                        let image = try state.rendered()
                        let updated = try await self.model.saveEditedCapture(image, replacing: record)
                        editor?.onClose = nil; self.editors.removeValue(forKey: record.id); editor?.close()
                        await self.present(updated, replacing: record.id)
                    } catch { state.error = error.localizedDescription; state.saving = false; editor?.standardWindowButton(.closeButton)?.isEnabled = true }
                }
            }, cancel: { [weak editor] in editor?.close() }))
            editors[record.id] = editor
            cards.first { $0.id == record.id }?.panel.orderOut(nil)
            editor.center(); editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        } catch { model.problem = error.localizedDescription }
    }
    func dismiss(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        retire(cards.remove(at: index).panel, upwards: false); layout()
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
        if !value { retiring.forEach { $0.close() }; retiring = [] }
        cards.forEach { if value && editors[$0.id] == nil { $0.panel.orderFrontRegardless() } else { $0.panel.orderOut(nil) } }
    }
    private func cardHeight(_ id: UUID) -> CGFloat {
        if model.formulaResults[id] != nil { return 280 }
        guard let record = model.captures.first(where: { $0.id == id }) else { return 184 }
        return min(220, max(90, 252 * CGFloat(record.pixelHeight) / CGFloat(record.pixelWidth) + 16))
    }
    private func layout() {
        guard let frame = (screen.flatMap { candidate in NSScreen.screens.first { $0 == candidate } } ?? NSScreen.main)?.visibleFrame else { return }
        let limit = max(1, min(5, model.visibleCaptures))
        var available = frame.height - 40, capacity = 0
        for card in cards.prefix(limit) {
            let height: CGFloat = cardHeight(card.id)
            if capacity > 0 && available < height { break }
            available -= height + 12; capacity += 1
        }
        while cards.count > max(1, capacity) { retire(cards.removeLast().panel, upwards: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            var y = frame.minY + 20
            for card in cards {
                let formula = model.formulaResults[card.id] != nil
                let height = cardHeight(card.id)
                let width: CGFloat = formula ? 380 : 268
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
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let thumbnail: NSImage
    let edit: () -> Void
    let dismiss: () -> Void
    @ObservedObject var state = CaptureCardState()
    var body: some View {
        if let result = model.formulaResults[record.id] {
            FormulaResultCard(model: model, record: record, result: result, dismiss: dismiss)
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
                    action("Read Text", symbol: "text.viewfinder") { model.selectCapture(record, action: .text) }.disabled(model.busy)
                    action("Recognise Formula", symbol: "function") { model.selectCapture(record, action: .formula) }.disabled(model.busy)
                }.buttonStyle(.plain).foregroundStyle(.white).padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state.hovering {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).padding(7).background(.ultraThinMaterial, in: Circle()) }
                    .buttonStyle(.plain).padding(8).help("Close preview · keep saved capture").accessibilityLabel("Close preview")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .padding(3).onHover { value in withAnimation(.easeOut(duration: 0.15)) { state.hovering = value }; if !value { state.copied = false } }
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
private final class CaptureHistoryState: ObservableObject { @Published var limit = 100; @Published var query = ""; @Published var matches = Set<UUID>() }

struct CaptureHistoryView: View {
    @ObservedObject var model: Workbench
    let show: (CaptureRecord) -> Void
    @ObservedObject private var state = CaptureHistoryState()
    private var matchingRecords: [CaptureRecord] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.captures.filter { record in
            query.isEmpty || state.matches.contains(record.id)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Capture History").font(.title2.weight(.semibold)); Spacer(); Button("Open Folder", action: model.revealCaptures) }
            Text("\(model.captures.count) saved captures · closing a preview keeps its original file.").font(.caption).foregroundStyle(.secondary)
            TextField("Search formulas or filenames", text: $state.query).textFieldStyle(.roundedBorder).onChange(of: state.query) { state.limit = 100 }
            List {
                ForEach(matchingRecords.prefix(state.limit)) { record in
                    HStack {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(record.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                            Text("\(record.pixelWidth) × \(record.pixelHeight) · \(record.fileName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let formula = model.savedFormulas[record.id] {
                            Text(formula.latex).font(.caption.monospaced()).lineLimit(1).frame(maxWidth: 150)
                            Button("Formula") { model.openSavedFormula(record.id) }.disabled(model.busy)
                        }
                        Button("Copy") { Task { _ = await model.copyCapture(record) } }
                        Button("Preview") { show(record) }
                        if model.dropbox.connected { Button("Dropbox") { model.dropbox.upload(record) }.disabled(model.busy) }
                        if model.googleDrive.connected { Button("Drive") { model.googleDrive.upload(record) }.disabled(model.busy) }
                    }.padding(.vertical, 4)
                }
                if state.limit < matchingRecords.count { Button("Show More") { state.limit += 100 } }
            }
            if model.captures.isEmpty { Text("Your next capture will appear here.").foregroundStyle(.secondary) }
        }.padding(20).frame(minWidth: 560, minHeight: 340)
        .task(id: state.query) {
            let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { state.matches = []; return }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let matches = try await model.searchCaptures(query)
                guard !Task.isCancelled else { return }
                state.matches = matches
            } catch is CancellationError {} catch { model.problem = error.localizedDescription }
        }
    }
}

@MainActor
private final class CaptureEditWindow: NSWindow {
    var onClose: (() -> Void)?
    override func close() { let callback = onClose; onClose = nil; super.close(); callback?() }
}
