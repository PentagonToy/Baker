import AppKit
import BakerCore
import SwiftUI

enum CaptureHistoryFilter: String, CaseIterable {
    case all = "All", images = "Images", formulas = "Formulas", videos = "Videos", gifs = "GIFs"
    func includes(formula: Bool) -> Bool { self == .all || (self == .formulas && formula) || (self == .images && !formula) }
}
enum CaptureHistoryItem: Identifiable {
    case image(CaptureRecord), recording(RecordingRecord)
    var id: UUID { switch self { case .image(let r): return r.id; case .recording(let r): return r.id } }
    var date: Date { switch self { case .image(let r): return r.createdAt; case .recording(let r): return r.createdAt } }
}
@MainActor enum CaptureHistoryPresentation {
    private static let relativeDate: RelativeDateTimeFormatter = {
        let value = RelativeDateTimeFormatter(); value.unitsStyle = .abbreviated; return value
    }()
    static func age(_ date: Date, relativeTo now: Date = Date()) -> String { abs(date.timeIntervalSince(now)) < 30 ? "Just now" : relativeDate.localizedString(for: date, relativeTo: now) }
}
@MainActor private final class CaptureHistoryState: ObservableObject {
    @Published var limit = 100
    @Published var query = ""
    @Published var filter = CaptureHistoryFilter.all
    @Published var matches = Set<UUID>()
    @Published var selected: UUID?
    @Published var searching = false
    var searchToken = UUID()
}

struct CaptureHistoryView: View {
    @ObservedObject var model: Workbench
    let show: (CaptureRecord) -> Void
    @StateObject private var state = CaptureHistoryState()
    private var records: [CaptureRecord] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.captures.filter {
            state.filter.includes(formula: model.savedFormulas[$0.id] != nil) && (query.isEmpty || state.matches.contains($0.id))
        }
    }
    private var items: [CaptureHistoryItem] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = model.recordings.filter {
            (state.filter == .all || (state.filter == .gifs && $0.isGIF) || (state.filter == .videos && !$0.isGIF))
                && (query.isEmpty || $0.fileName.localizedCaseInsensitiveContains(query))
        }
        var result: [CaptureHistoryItem] = records.map { CaptureHistoryItem.image($0) }
        result.append(contentsOf: media.map { CaptureHistoryItem.recording($0) })
        result.sort { (first: CaptureHistoryItem, second: CaptureHistoryItem) -> Bool in first.date > second.date }
        return result
    }
    var body: some View {
        historyContent
            .buttonStyle(BakerButtonStyle()).padding(20).font(BakerTypography.body).tint(BakerTheme.accent).background(BakerTheme.background)
            .frame(minWidth: 720, minHeight: 460)
            .onChange(of: state.query) { state.limit = 100 }
            .onChange(of: state.filter) { state.limit = 100 }
            .task(id: searchIdentity) { await search() }
    }
    private var searchIdentity: String {
        let revision = String(model.historyRevision)
        let count = String(model.captures.count)
        return [state.query, revision, count].joined(separator: ":")
    }
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            historyHeader
            filters
            searchField
            results

        }
    }
    private var historyHeader: some View {
        HStack {
            Text("Capture History").font(BakerTypography.title)
            Spacer()
            Button(action: model.revealCaptures) { Label("Open Folder", systemImage: "folder") }
        }
    }
    private var filters: some View {
        HStack(spacing: 14) {
            Picker("Capture type", selection: $state.filter) {
                ForEach(CaptureHistoryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 460)
            Spacer()
            Text("\(items.count) captures").font(BakerTypography.supporting).foregroundStyle(.secondary)
        }
    }
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search formulas or filenames", text: $state.query).textFieldStyle(.plain)
            if state.searching { ProgressView().controlSize(.small) }
            if !state.query.isEmpty {
                Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).frame(width: 28, height: 28).accessibilityLabel("Clear search")
            }
        }.padding(10).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
    @ViewBuilder
    private var results: some View {
        if items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.stack").font(.system(size: 36)).foregroundStyle(.secondary)
                Text(model.captures.isEmpty && model.recordings.isEmpty ? "Your captures will appear here" : state.searching ? "Searching…" : "No matching captures").font(.headline)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)], spacing: 16) {
                    ForEach(Array(items.prefix(state.limit))) { item in
                        switch item {
                        case .image(let record):
                            CaptureHistoryCard(model: model, record: record, selected: state.selected == record.id,
                                select: { state.selected = record.id }, show: { show(record) })
                        case .recording(let record):
                            RecordingHistoryCard(model: model, record: record)
                        }
                    }
                }.padding(2)
                if state.limit < items.count { Button("Show More") { state.limit += 100 }.padding(.top, 16) }
            }
        }
    }
    private func search() async {
        let token = UUID(); state.searchToken = token
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { state.matches = []; state.searching = false; return }
        state.searching = true
        defer { if state.searchToken == token { state.searching = false } }
        do {
            try await Task.sleep(nanoseconds: 180_000_000)
            let matches = try await model.searchCaptures(query)
            guard !Task.isCancelled, state.searchToken == token else { return }
            state.matches = matches
        } catch is CancellationError {} catch { model.report(error, fallback: .storageFailed) }
    }
}

@MainActor private final class CaptureHistoryCardState: ObservableObject {
    @Published var image: NSImage?
    @Published var error = false
    @Published var copied = false
    @Published var previewing = false
    init(image: NSImage? = nil) { self.image = image }
}
private struct CaptureHistoryCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let selected: Bool
    let select: () -> Void
    let show: () -> Void
    @StateObject private var state = CaptureHistoryCardState()
    @MainActor init(model: Workbench, record: CaptureRecord, selected: Bool, select: @escaping () -> Void, show: @escaping () -> Void) {
        self.model = model; self.record = record; self.selected = selected; self.select = select; self.show = show
        _state = StateObject(wrappedValue: CaptureHistoryCardState(image: model.cachedThumbnail(record.id)))
    }
    private var formula: Bool { model.savedFormulas[record.id] != nil }
    private func openPreview() { if record.isVector { state.previewing = true } else { show() } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                if let image = state.image { Image(nsImage: image).resizable().scaledToFit().padding(6).transition(.opacity) }
                else if state.error { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small) }
            }.aspectRatio(1.618, contentMode: .fit).contentShape(Rectangle())
                .onTapGesture(count: 2) { if formula { model.openSavedFormula(record.id) } else { openPreview() } }
                .onTapGesture(perform: select)
                .accessibilityLabel(formula ? "Formula capture" : "Image capture")
            HStack {
                Label(formula ? "Formula" : record.isVector ? "SVG" : "Image", systemImage: formula ? "sum" : record.isVector ? "point.topleft.down.to.point.bottomright.curvepath" : "photo").font(BakerTypography.section)
                Spacer()
                Text(CaptureHistoryPresentation.age(record.createdAt)).font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(1)
                    .help(record.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            Text("\(record.pixelWidth) × \(record.pixelHeight) px").font(BakerTypography.supporting).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(formula ? "Open Formula" : "Show Preview") { if formula { model.openSavedFormula(record.id) } else { openPreview() } }.disabled(model.busy)
                Spacer(minLength: 0)
                Button {
                    Task { state.copied = await model.copyCapture(record) }
                } label: { Label(state.copied ? "Copied" : "Copy", systemImage: state.copied ? "checkmark" : "doc.on.doc") }
                    .frame(width: 88).help("Copy the capture image").accessibilityLabel("Copy Image")
            }.buttonStyle(BakerButtonStyle())
        }.padding(12).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? BakerTheme.accent : Color.secondary.opacity(0.18), lineWidth: selected ? 2 : 1))
            .animation(BakerMotion.selection(reduced: reduceMotion), value: selected)
            .animation(BakerMotion.selection(reduced: reduceMotion), value: state.copied)
            .contextMenu {
                if formula { Button("Open Formula") { model.openSavedFormula(record.id) }.disabled(model.busy) }
                Button("Show Capture Preview", action: openPreview)
                Button("Copy Image") { Task { state.copied = await model.copyCapture(record) } }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.captureURL(record)]) }
            }
            .task(id: record.id.uuidString + ":" + String(model.historyRevision)) {
                state.error = false
                do {
                    let image = try await model.thumbnail(record)
                    guard !Task.isCancelled else { return }
                    state.image = image
                } catch is CancellationError {} catch { state.error = true }
            }
            .sheet(isPresented: $state.previewing) { CaptureVectorPreview(model: model, record: record) }
            .onDisappear { state.image = nil }
    }
}


private struct RecordingHistoryCard: View {
    @ObservedObject var model: Workbench
    let record: RecordingRecord
    @StateObject private var state = CaptureHistoryCardState()
    private var url: URL { model.recordingURL(record) }
    private func open() { NSWorkspace.shared.open(url) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                if let image = state.image { Image(nsImage: image).resizable().scaledToFit().padding(6) }
                else { Image(systemName: record.isGIF ? "photo.on.rectangle.angled" : "play.rectangle").font(.largeTitle).foregroundStyle(.secondary) }
            }.aspectRatio(1.618, contentMode: .fit).contentShape(Rectangle()).onTapGesture(count: 2, perform: open)
            HStack {
                Label(record.isGIF ? "GIF" : "Video", systemImage: record.isGIF ? "photo.on.rectangle.angled" : "video").font(BakerTypography.section)
                Spacer()
                Text(CaptureHistoryPresentation.age(record.createdAt)).font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(1)
                    .help(record.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            Text(record.fileName).font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Button(record.isGIF ? "Open GIF" : "Play Video", action: open)
                Spacer()
                Button { state.copied = model.copyRecording(record) } label: {
                    Label(state.copied ? "Copied" : "Copy", systemImage: state.copied ? "checkmark" : "doc.on.doc")
                }.frame(width: 88).help("Copy the recording file")
            }.buttonStyle(BakerButtonStyle())
        }.padding(12).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.18)))
            .contextMenu {
                Button(record.isGIF ? "Open GIF" : "Play Video", action: open)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            .task(id: record.id) {
                do { let image = try await model.recordingThumbnail(record); if !Task.isCancelled { state.image = image } }
                catch { state.error = true }
            }
            .onDisappear { state.image = nil }
    }
}

@MainActor private final class CaptureVectorPreviewState: ObservableObject {
    @Published var image: NSImage?
    @Published var error: String?
}
/// History opens vector files without entering the raster editor.
private struct CaptureVectorPreview: View {
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = CaptureVectorPreviewState()
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("SVG Preview").font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let image = state.image {
                CaptureDragView(image: image, file: model.captureURL(record), edit: {}, completed: {})
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.error { Text(error).foregroundStyle(.secondary).frame(maxHeight: .infinity) }
            else { ProgressView().frame(maxHeight: .infinity) }
            HStack {
                Text("SVG · \(record.pixelWidth) × \(record.pixelHeight)").foregroundStyle(.secondary)
                Spacer()
                Button("Copy SVG") { Task { _ = await model.copyCapture(record) } }.disabled(state.image == nil)
                Button("Save As…") { model.saveCapture(record) }.disabled(state.image == nil)
            }
        }.padding(20).frame(minWidth: 620, minHeight: 420).background(BakerTheme.background)
            .task { do { state.image = try await model.vectorImage(record) } catch { state.error = error.localizedDescription } }
    }
}
