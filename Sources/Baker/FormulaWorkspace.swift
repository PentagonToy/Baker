import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

private enum FormulaPreviewMode: String, CaseIterable { case original = "Original", rendered = "Rendered", both = "Both" }
@MainActor
private final class FormulaWorkspaceState: ObservableObject {
    @Published var previewMode: FormulaPreviewMode = .rendered
    @Published var original: NSImage?
    @Published var originalID: UUID?
    @Published var originalError: String?
    @Published var showUnicodeWarning = false
    @Published var dropTargeted = false
    @Published var showingHistory = false
    @Published var historyFormat: OutputFormat = .latex
}

struct FormulaWorkspace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var model: Workbench
    let showHistory: () -> Void
    @StateObject private var state = FormulaWorkspaceState()
    private var record: CaptureRecord? { model.captures.first { $0.id == model.focusedFormulaID } }
    private var result: FormulaResult? { model.formulaInputPending ? nil : model.focusedFormulaID.flatMap { model.formulaResults[$0] } }
    private var formulaRecords: [CaptureRecord] { model.captures.filter { model.savedFormulas[$0.id] != nil || model.formulaResults[$0.id] != nil } }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                toolbar(compact: false)
                toolbar(compact: true)
            }
            Divider()
            if !state.showingHistory && result != nil {
            HStack {
                Text("Formula").font(BakerTypography.section)
                if let provider = result?.recognitionProvider { RecognitionProviderLabel(provider: provider).help(result?.model ?? provider) }
                Spacer()
                Picker("Preview", selection: $state.previewMode) {
                    ForEach(FormulaPreviewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Preview")
                    .controlSize(.small).frame(width: 240)
            }.padding(.horizontal, 18).padding(.vertical, 12)
            }
            if state.showingHistory {
                FormulaHistoryView(model: model, records: formulaRecords, format: $state.historyFormat,
                    selectedID: model.focusedFormulaID, open: select, showCaptures: showHistory)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let result, let record {
                        if model.formulaInputPending {
                            inputSlot
                        } else if state.previewMode != .rendered {
                            preview("Original") {
                                if state.originalID == record.id, let image = state.original {
                                    GeometryReader { geometry in
                                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                            .frame(width: min(geometry.size.width, CGFloat(record.pixelWidth) / displayScale),
                                                   height: min(geometry.size.height, CGFloat(record.pixelHeight) / displayScale))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }.padding(8)
                                }
                                else if let error = state.originalError { Text(error).font(BakerTypography.supporting).foregroundStyle(.black).padding(12) }
                                else { ProgressView().controlSize(.small) }
                            }
                            Text("\(record.pixelWidth) × \(record.pixelHeight) px · Original capture")
                                .font(BakerTypography.supporting).foregroundStyle(.secondary)
                        }
                        if model.formulaInputPending || state.previewMode != .original {
                            preview(model.formulaInputPending ? "Previous result" : "Rendered") {
                                if result.phase == .recognising {
                                    VStack(spacing: 10) { ProgressView(); Text(result.recognitionMessage).font(BakerTypography.body).foregroundStyle(.black) }
                                } else if let image = result.preview {
                                    Image(nsImage: image).resizable().scaledToFit().blendMode(colorScheme == .dark ? .normal : .multiply).padding(12)
                                } else if result.phase == .failed {
                                    VStack(spacing: 10) {
                                        Text(result.error).font(BakerTypography.body).foregroundStyle(.black).textSelection(.enabled)
                                        FormulaFailureActions(model: model, record: record, failure: result.failure)
                                    }.padding(16)
                                } else if let error = result.previewError {
                                    VStack(spacing: 8) { Text(result.latex).font(.system(.body, design: .monospaced)); Text(error).font(BakerTypography.supporting) }
                                        .foregroundStyle(.black).padding(14)
                                } else { ProgressView("Rendering…").foregroundStyle(.black) }
                            }
                        }
                        if result.phase == .ready {
                            if let confidence = result.confidence {
                                HStack(spacing: 10) {
                                    Text("Model score").font(BakerTypography.supporting).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(confidence, format: .percent.precision(.fractionLength(0))).font(BakerTypography.supporting.monospacedDigit())
                                }.padding(.horizontal, 2).help("Model token confidence, not a verified probability that the entire equation is correct. Compare the original before using it.")
                            } else if result.wasEdited {
                                Text("Edited").font(BakerTypography.supporting).foregroundStyle(.secondary)
                            }
                            DisclosureGroup("Recognition details") {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Model: " + result.model)
                                    if let score = result.originalConfidence { Text("Original OCR score: " + score.formatted(.percent.precision(.fractionLength(1)))) }
                                    if let method = result.confidenceMethod { Text("Score method: " + method) }
                                    if let diagnostics = result.diagnostics {
                                        Text("Original OCR: \(diagnostics.tokenCount) tokens · \(diagnostics.ambiguousTokenCount) below 80% token confidence")
                                        Text("Lowest token score: " + diagnostics.minimumTokenProbability.formatted(.percent.precision(.fractionLength(1))))
                                        Text("Token uncertainty is not a per-symbol error count. Edited output is not rescored.").foregroundStyle(.secondary)
                                    }
                                    if result.wasEdited { Text("Original OCR LaTeX: " + result.originalLatex).textSelection(.enabled) }
                                    Button("Recognise Again") {
                                        model.recogniseSavedFormula(record)
                                    }.disabled(model.busy)
                                }.font(BakerTypography.supporting).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(spacing: 0) {
                                formatRow(.latex, text: result.style.format(result.latex), result: result, id: record.id)
                                Divider().padding(.horizontal, 14)
                                formatRow(.markdown, text: LatexCopyStyle.displayDollar.format(result.latex), result: result, id: record.id)
                                Divider().padding(.horizontal, 14)
                                formatRow(.keynote, text: result.keynote, result: result, id: record.id)
                                Divider().padding(.horizontal, 14)
                                formatRow(.unicode, text: result.unicode, result: result, id: record.id)
                            }.background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.border))
                            HStack {
                                if result.format == .latex {
                                    Picker("LaTeX style", selection: Binding(get: { result.style }, set: { model.chooseLatexStyle(record.id, $0) })) {
                                        ForEach(LatexCopyStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }.frame(maxWidth: 300)
                                } else if result.format == .markdown {
                                    Text("Display maths · $$ delimiters on separate lines").font(BakerTypography.supporting).foregroundStyle(.secondary)
                                } else if result.format == .keynote {
                                    Text(result.keynoteWarning.isEmpty ? "Keynote: bare maths with compatible matrix environments." : result.keynoteWarning)
                                        .font(BakerTypography.supporting).foregroundStyle(.secondary).textSelection(.enabled)
                                } else { Text(result.warning).font(BakerTypography.supporting).foregroundStyle(.secondary) }
                                Spacer()
                            }
                        }
                    } else {
                        inputSlot
                        if !formulaRecords.isEmpty {
                            FormulaHistoryView(model: model, records: Array(formulaRecords.prefix(6)), format: $state.historyFormat,
                                selectedID: nil, recent: true, open: select, showCaptures: { state.showingHistory = true })
                        }
                    }
                }.padding(18)
            }.scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                Text(model.busy || state.showingHistory ? model.status : result?.copyStatus ?? "Ready").lineLimit(1)
                Spacer()
                Text("\(formulaRecords.count) saved \(formulaRecords.count == 1 ? "result" : "results")").foregroundStyle(.secondary)
            }.font(BakerTypography.supporting).padding(.horizontal, 18).padding(.vertical, 10)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $state.dropTargeted) { providers in
            guard !model.busy, let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                guard let url = (value as? URL) ?? (value as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) else { return }
                Task { @MainActor in model.importFormulaImage(url) }
            }
            return true
        }
        .overlay { if state.dropTargeted { RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.accent, lineWidth: 3).allowsHitTesting(false) } }
        .font(BakerTypography.body).tint(BakerTheme.accent)
        .foregroundStyle(BakerTheme.ink).background(BakerTheme.background)
        .animation(nil, value: state.previewMode)
        .frame(minWidth: 660, minHeight: 520)
        .onChange(of: model.focusedFormulaID) { if model.focusedFormulaID != nil { state.showingHistory = false } }
        .onChange(of: model.formulaInputPending) { if model.formulaInputPending { state.showingHistory = false } }
        .task(id: (model.focusedFormulaID?.uuidString ?? "") + state.previewMode.rawValue + String(state.showingHistory)) {
            state.original = nil; state.originalID = nil; state.originalError = nil
            guard !state.showingHistory, state.previewMode != .rendered, let record else { return }
            do {
                let image = try await model.originalPreview(record)
                guard !Task.isCancelled, model.focusedFormulaID == record.id else { return }
                state.original = image; state.originalID = record.id
            } catch {
                guard !Task.isCancelled, model.focusedFormulaID == record.id else { return }
                state.originalError = "The original capture could not be opened."
            }
        }
        .onDisappear { state.original = nil; state.originalID = nil }
    }
    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 10) {
                Button { model.capture(scrolling: false, action: .formula) } label: { Label("Capture", systemImage: "viewfinder") }.labelStyle(BakerToolbarLabelStyle()).help("Capture another formula")
                Button { model.openImage(asFormula: true) } label: { Label("Image…", systemImage: "photo.badge.plus") }
                Button { state.showingHistory = false; model.formulaInputPending = true; state.previewMode = .both } label: { Label("New", systemImage: "plus") }.help("Drop or open another formula image")
                if !state.showingHistory && !formulaRecords.isEmpty {
                Divider().frame(height: 20)
                Button { navigate(1) } label: { Image(systemName: "chevron.left") }.disabled(!canNavigate(1))
                Text(position).monospacedDigit().font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button { navigate(-1) } label: { Image(systemName: "chevron.right") }.disabled(!canNavigate(-1))
                }
                Spacer()
                Picker("Workspace view", selection: $state.showingHistory) {
                    Image(systemName: "square.grid.2x2").accessibilityLabel("Formula History").tag(true)
                    Image(systemName: "rectangle").accessibilityLabel("Formula Detail").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 72).help("Formula History or Detail")
                if !state.showingHistory, !model.formulaInputPending, let id = model.focusedFormulaID { Button { model.editFormula(id) } label: { Label("Edit", systemImage: "square.and.pencil") }.disabled(result?.phase != .ready) }
            }.labelStyle(BakerToolbarLabelStyle(compact: compact)).buttonStyle(BakerButtonStyle()).controlSize(.regular).foregroundStyle(.primary).disabled(model.busy).padding(.horizontal, 18).padding(.vertical, 12).background(BakerTheme.sidebar)
    }
    private func preview<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(BakerTypography.supporting).foregroundStyle(.secondary)
                Spacer()
                if title == "Original", let record {
                    Button { Task { _ = await model.copyCapture(record) } } label: { Label("Copy Image", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless).font(BakerTypography.supporting)
                }
            }
            ZStack { RoundedRectangle(cornerRadius: 10).fill(BakerTheme.paper); content() }
                .frame(maxWidth: .infinity).frame(height: state.previewMode == .both && title == "Original" ? 96 : 160)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.gray.opacity(0.18)))
        }
    }
    private func formatRow(_ format: OutputFormat, text: String, result: FormulaResult, id: UUID) -> some View {
        HStack(spacing: 10) {
            Text(format.rawValue).font(BakerTypography.section).frame(width: 78, alignment: .leading)
            ScrollView(.horizontal) { Text((format == .unicode && result.unicodeUnavailable ? "Unavailable for this formula" : text).replacingOccurrences(of: "\n", with: " ↵ ")).font(format == .unicode ? Font(model.selectedMathFont.resolvedFont.withSize(16)) : .system(size: 13, design: .monospaced)).lineLimit(1).textSelection(.enabled) }.scrollContentBackground(.hidden).frame(height: format == .unicode ? 24 : 18)
            if format == .unicode && result.unicodeUnavailable { Button { state.showUnicodeWarning.toggle() } label: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                    .buttonStyle(.borderless).help(result.warning).accessibilityLabel("Unicode representation warning: " + result.warning)
                    .popover(isPresented: $state.showUnicodeWarning, arrowEdge: .bottom) {
                        Text(result.warning).font(BakerTypography.body).padding(14).frame(width: 300).fixedSize(horizontal: false, vertical: true)
                    } }
            Label("Copied", systemImage: "checkmark.circle.fill").font(BakerTypography.supporting).foregroundStyle(BakerTheme.success)
                .frame(width: 68).opacity(result.copiedFormat == format ? 1 : 0)
                .accessibilityHidden(result.copiedFormat != format)
            Button { model.chooseFormulaFormat(id, format) } label: { Image(systemName: "doc.on.doc").font(.system(size: 14)).frame(width: 16, height: 20) }
                .buttonStyle(BakerButtonStyle()).accessibilityLabel("Copy \(format.rawValue)").disabled(format == .unicode && text.isEmpty).help("Select and copy \(format.rawValue)")
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 46).background(result.format == format ? BakerTheme.accent.opacity(0.065) : Color.clear)
            .contentShape(Rectangle()).onTapGesture { model.chooseFormulaFormat(id, format) }
            .animation(BakerMotion.selection(reduced: reduceMotion), value: result.copiedFormat)
    }
    private var inputSlot: some View {
        preview("New formula") {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus").font(.system(size: 23))
                Text("Drop a formula image").font(BakerTypography.section)
                Text("Drop a capture here, or choose Image… above.").font(BakerTypography.supporting)
            }.foregroundStyle(.black.opacity(0.75)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func select(_ entry: CaptureRecord) {
        state.showingHistory = false
        model.formulaInputPending = false
        if model.savedFormulas[entry.id] != nil { model.openSavedFormula(entry.id) }
        else { model.focusedFormulaID = entry.id }
    }
    private var position: String {
        if model.formulaInputPending { return "New · \(formulaRecords.count) saved" }
        guard let index = formulaRecords.firstIndex(where: { $0.id == model.focusedFormulaID }) else { return "0 / \(formulaRecords.count)" }
        return "\(formulaRecords.count - index) / \(formulaRecords.count)"
    }
    private func canNavigate(_ offset: Int) -> Bool {
        if model.formulaInputPending { return offset == 1 && !formulaRecords.isEmpty }
        guard let index = formulaRecords.firstIndex(where: { $0.id == model.focusedFormulaID }) else { return false }
        return formulaRecords.indices.contains(index + offset)
    }
    private func navigate(_ offset: Int) {
        if model.formulaInputPending {
            if offset == 1, let entry = formulaRecords.first(where: { $0.id == model.focusedFormulaID }) ?? formulaRecords.first { select(entry) }
            return
        }
        guard let index = formulaRecords.firstIndex(where: { $0.id == model.focusedFormulaID }), canNavigate(offset) else { return }
        select(formulaRecords[index + offset])
    }
}
