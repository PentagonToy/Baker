import AppKit
import BakerCore
import SwiftUI
import Combine

@MainActor
final class CaptureOverlayController {
    private let model: Workbench
    private var cards: [(id: UUID, panel: NSPanel)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var visible = true
    private var screen: NSScreen?

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
    private func present(_ record: CaptureRecord) async {
        do {
            let thumbnail = try await model.thumbnail(record)
            if let index = cards.firstIndex(where: { $0.id == record.id }) { cards.remove(at: index).panel.close() }
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 268, height: 184), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = CaptureHostingView(rootView: CaptureCardView(model: model, record: record, thumbnail: thumbnail, dismiss: { [weak self] in self?.dismiss(record.id) }))
            screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            cards.insert((record.id, panel), at: 0)
            panel.alphaValue = 0
            layout()
            if visible { panel.orderFrontRegardless() }
            await NSAnimationContext.runAnimationGroup { context in context.duration = 0.2; panel.animator().alphaValue = 1 }
        } catch { model.problem = error.localizedDescription }
    }
    func dismiss(_ id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards.remove(at: index).panel.close(); layout()
    }
    func setVisible(_ value: Bool) {
        visible = value
        cards.forEach { if value { $0.panel.orderFrontRegardless() } else { $0.panel.orderOut(nil) } }
    }
    private func layout() {
        guard let frame = (screen.flatMap { candidate in NSScreen.screens.first { $0 == candidate } } ?? NSScreen.main)?.visibleFrame else { return }
        let limit = max(1, min(5, model.visibleCaptures))
        var available = frame.height - 40, capacity = 0
        for card in cards.prefix(limit) {
            let height: CGFloat = model.formulaResults[card.id] == nil ? 184 : 280
            if capacity > 0 && available < height { break }
            available -= height + 12; capacity += 1
        }
        while cards.count > max(1, capacity) { cards.removeLast().panel.close() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            var y = frame.minY + 20
            for card in cards {
                let formula = model.formulaResults[card.id] != nil
                let height: CGFloat = formula ? 280 : 184
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
            Image(nsImage: thumbnail).resizable().scaledToFit().padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrag { NSItemProvider(contentsOf: model.captureURL(record)) ?? NSItemProvider() }
            if state.hovering {
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                HStack(spacing: 3) {
                    action(state.copying ? "Copying…" : state.copied ? "Copied" : "Copy", symbol: state.copying ? "hourglass" : state.copied ? "checkmark" : "doc.on.doc") {
                        state.copying = true
                        Task { state.copied = await model.copyCapture(record); state.copying = false }
                    }.disabled(state.copying)
                    action("Save As…", symbol: "square.and.arrow.down") { model.saveCapture(record) }
                    action("Pin", symbol: "pin") { model.selectCapture(record, action: .image) }.disabled(model.busy)
                    Divider().frame(height: 18).overlay(.white.opacity(0.3))
                    action("Read Text", symbol: "text.viewfinder") { model.selectCapture(record, action: .text) }.disabled(model.busy)
                    action("Recognise Formula", symbol: "function") { model.selectCapture(record, action: .formula) }.disabled(model.busy)
                }.buttonStyle(.plain).foregroundStyle(.white).padding(10)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                    if model.activeCaptureID == record.id && model.busy {
                        ProgressView().controlSize(.mini)
                        Text("Processing…")
                    } else if model.activeCaptureID == record.id && !model.output.isEmpty {
                        Text("\(model.format.rawValue) ready")
                    } else { Text("Saved") }
                    Spacer()
                    Text("\(record.pixelWidth) × \(record.pixelHeight)")
                }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial)
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
            Button("Save As…") { model.saveCapture(record) }
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
private final class CaptureHistoryState: ObservableObject { @Published var limit = 100 }

struct CaptureHistoryView: View {
    @ObservedObject var model: Workbench
    let show: (CaptureRecord) -> Void
    @ObservedObject private var state = CaptureHistoryState()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Capture History").font(.title2.weight(.semibold)); Spacer(); Button("Open Folder", action: model.revealCaptures) }
            Text("\(model.captures.count) saved captures · closing a preview keeps its original file.").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(model.captures.prefix(state.limit)) { record in
                    HStack {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(record.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                            Text("\(record.pixelWidth) × \(record.pixelHeight) · \(record.fileName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Copy") { Task { _ = await model.copyCapture(record) } }
                        Button("Preview") { show(record) }
                    }.padding(.vertical, 4)
                }
                if state.limit < model.captures.count { Button("Show More") { state.limit += 100 } }
            }
            if model.captures.isEmpty { Text("Your next capture will appear here.").foregroundStyle(.secondary) }
        }.padding(20).frame(minWidth: 560, minHeight: 340)
    }
}
