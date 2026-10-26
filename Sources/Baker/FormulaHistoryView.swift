import AppKit
import BakerCore
import SwiftUI

@MainActor private final class FormulaHistoryState: ObservableObject {
    @Published var query = ""
    @Published var limit = 60
    @Published var selection: Set<UUID> = []
    @Published var pendingDeletion: Set<UUID> = []
    @Published var confirmingDeletion = false
}

/// Reuses bounded capture thumbnails. Browsing never runs OCR or starts a renderer per card.
struct FormulaHistoryView: View {
    @ObservedObject var model: Workbench
    let records: [CaptureRecord]
    @Binding var format: OutputFormat
    let selectedID: UUID?
    var recent = false
    let open: (CaptureRecord) -> Void
    let showCaptures: () -> Void
    @StateObject private var state = FormulaHistoryState()
    private var matches: [CaptureRecord] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter {
            let source = model.formulaResults[$0.id]?.latex ?? model.savedFormulas[$0.id]?.latex ?? ""
            return source.localizedCaseInsensitiveContains(query) ||
                (model.savedFormulas[$0.id]?.matchesSearchText.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    var body: some View {
        if recent { content }
        else { ScrollView { content.padding(18) }.scrollContentBackground(.hidden) }
    }
    private var content: some View {
        let filtered = matches
        return VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { heading(count: filtered.count); Spacer(); copyPicker }
                VStack(alignment: .leading, spacing: 10) { heading(count: filtered.count); copyPicker }
            }
            if !recent {
                TextField("Search formulas", text: $state.query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search formula history")
            }
            if !state.selection.isEmpty {
                HStack(spacing: 12) {
                    Text("\(state.selection.count) selected").font(BakerTypography.supporting.monospacedDigit())
                    Button("Deselect All") { state.selection = [] }.buttonStyle(.borderless)
                    Spacer()
                    Button { confirmDeletion(state.selection) } label: { Label("Delete Selected…", systemImage: "trash") }
                        .buttonStyle(BakerButtonStyle()).disabled(model.busy)
                        .keyboardShortcut(.delete, modifiers: .command)
                }
            }
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 24)).foregroundStyle(.secondary)
                    Text(records.isEmpty ? "Your formulas will appear here" : "No matching formulas")
                        .font(BakerTypography.section)
                }.frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                    ForEach(Array(filtered.prefix(state.limit))) { record in
                        FormulaHistoryTile(model: model, record: record, format: format,
                            selected: state.selection.contains(record.id), focused: record.id == selectedID,
                            open: { activate(record) }, showDetail: { open(record) }, select: { toggleSelection(record.id) },
                            delete: { confirmDeletion(state.selection.contains(record.id) ? state.selection : [record.id]) })
                    }
                }
                if filtered.count > state.limit {
                    Button("Show More") { state.limit += 60 }.buttonStyle(BakerButtonStyle())
                }
            }
        }.font(BakerTypography.body).foregroundStyle(BakerTheme.ink)
            .onChange(of: state.query) { state.limit = 60; state.selection = [] }
            .onChange(of: records.map(\.id)) { state.selection.formIntersection(Set(records.map(\.id))) }
            .alert(state.pendingDeletion.count == 1 ? "Delete this formula?" : "Delete \(state.pendingDeletion.count) formulas?", isPresented: $state.confirmingDeletion) {
                Button("Cancel", role: .cancel) { state.pendingDeletion = [] }
                Button("Delete", role: .destructive) {
                    let ids = state.pendingDeletion
                    state.pendingDeletion = []
                    Task { @MainActor in
                        do {
                            try await model.deleteFormulaHistory(ids)
                            state.selection.subtract(ids)
                        } catch { model.report(error, fallback: .storageFailed, context: "Formula history could not be updated:") }
                    }
                }
            } message: {
                Text("Saved formula text, edits and recognition details will be removed. Original capture images stay in Capture History. This cannot be undone.")
            }
    }
    private func toggleSelection(_ id: UUID) {
        guard !model.busy else { return }
        if !state.selection.insert(id).inserted { state.selection.remove(id) }
    }
    private func activate(_ record: CaptureRecord) {
        if !state.selection.isEmpty { state.selection = [record.id] }
        else { open(record) }
    }
    private func confirmDeletion(_ ids: Set<UUID>) {
        guard !model.busy, !ids.isEmpty else { return }
        state.pendingDeletion = ids
        state.confirmingDeletion = true
    }
    private func heading(count: Int) -> some View {
        HStack(spacing: 10) {
            Text(recent ? "Recent formulas" : "Formula History").font(BakerTypography.section)
            if !recent { Text("\(count)").font(BakerTypography.supporting.monospacedDigit()).foregroundStyle(.secondary) }
            Button(recent ? "See All" : "All Captures…", action: showCaptures)
                .buttonStyle(.borderless).font(BakerTypography.supporting)
        }
    }
    private var copyPicker: some View {
        Picker("Copy as", selection: $format) {
            ForEach([OutputFormat.latex, .markdown, .keynote, .unicode], id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).frame(width: 190).controlSize(.regular)
    }
}

@MainActor private final class FormulaHistoryTileState: ObservableObject {
    @Published var image: NSImage?
    @Published var copyMessage = ""
    @Published var copied = false
}
private struct FormulaHistoryTile: View {
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let format: OutputFormat
    let selected: Bool
    let focused: Bool
    let open: () -> Void
    let showDetail: () -> Void
    let select: () -> Void
    let delete: () -> Void
    @StateObject private var state = FormulaHistoryTileState()
    private var latex: String {
        if let result = model.formulaResults[record.id], result.phase == .ready { return result.latex }
        return model.savedFormulas[record.id]?.latex ?? ""
    }
    private var edited: Bool {
        guard let saved = model.savedFormulas[record.id] else { return false }
        return saved.originalLatex != saved.latex
    }
    var body: some View {
        VStack(spacing: 10) {
            Button(action: open) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(BakerTheme.paper)
                    if let image = state.image { Image(nsImage: image).resizable().scaledToFit().padding(12) }
                    else { Text(latex).font(.system(size: 13, design: .monospaced)).foregroundStyle(.black).lineLimit(4).padding(12) }
                }.overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(BakerTheme.accent)
                            .padding(6).background(BakerTheme.surface, in: Circle()).padding(6)
                    }
                }.frame(height: 112).frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy)
                .highPriorityGesture(TapGesture().modifiers(.command).onEnded { select() })
                .accessibilityLabel("Open formula: " + String(latex.prefix(180))).help("Click to open; Command-click to select multiple formulas")
            HStack {
                Text(CaptureHistoryPresentation.age(record.createdAt)).font(BakerTypography.supporting)
                    .foregroundStyle(.secondary).lineLimit(1)
                    .help(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                if edited {
                    Image(systemName: "pencil").font(BakerTypography.supporting).foregroundStyle(.secondary)
                        .accessibilityLabel("Edited result; thumbnail shows the original capture")
                        .help("Edited result; thumbnail shows the original capture")
                }
                Spacer(minLength: 4)
                Button {
                    state.copied = model.copyHistoryFormula(record.id, as: format)
                    state.copyMessage = state.copied ? "" : model.status
                } label: {
                    Label(state.copied ? "Copied" : "Copy", systemImage: state.copied ? "checkmark" : "doc.on.doc")
                }.buttonStyle(BakerButtonStyle()).accessibilityLabel(state.copied ? "Copied \(format.rawValue)" : "Copy \(format.rawValue)")
                    .help("Copy \(format.rawValue)").disabled(model.switchingStorage || model.formulaResults[record.id]?.phase == .recognising)
            }
            if !state.copyMessage.isEmpty {
                Text(state.copyMessage).font(BakerTypography.supporting).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(10).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected || focused ? BakerTheme.accent : BakerTheme.border, lineWidth: selected ? 2 : 1))
            .contextMenu {
                Button("Open Formula", action: showDetail).disabled(model.busy)
                Button("Copy \(format.rawValue)") { _ = model.copyHistoryFormula(record.id, as: format) }.disabled(model.busy)
                Button(selected ? "Deselect Formula" : "Select Formula", action: select).disabled(model.busy)
                Divider()
                Button(selected ? "Delete Selected Formulas…" : "Delete Formula…", role: .destructive, action: delete).disabled(model.busy)
            }
            .accessibilityValue(selected ? "Selected" : "")
            .task(id: record.id.uuidString + ":" + String(model.historyRevision)) {
                state.image = nil
                do {
                    let image = try await model.thumbnail(record)
                    guard !Task.isCancelled else { return }
                    state.image = image
                } catch { /* The saved LaTeX remains visible and copyable without an image. */ }
            }
            .task(id: state.copied) {
                guard state.copied else { return }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                state.copied = false
            }
            .onChange(of: format) { state.copied = false; state.copyMessage = "" }
            .onDisappear { state.image = nil }
    }
}
