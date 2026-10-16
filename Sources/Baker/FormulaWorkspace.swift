import AppKit
import BakerCore
import SwiftUI

private enum FormulaPreviewMode: String, CaseIterable { case original = "Original", rendered = "Rendered", both = "Both" }
@MainActor
private final class FormulaWorkspaceState: ObservableObject {
    @Published var previewMode: FormulaPreviewMode = .both
    @Published var original: NSImage?
    @Published var originalID: UUID?
    @Published var showUnicodeWarning = false
}

struct FormulaWorkspace: View {
    @ObservedObject var model: Workbench
    let showHistory: () -> Void
    @ObservedObject private var state = FormulaWorkspaceState()
    private var record: CaptureRecord? { model.captures.first { $0.id == model.focusedFormulaID } }
    private var result: FormulaResult? { model.focusedFormulaID.flatMap { model.formulaResults[$0] } }
    private var sessionRecords: [CaptureRecord] { model.captures.filter { model.formulaResults[$0.id] != nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { model.capture(scrolling: false, action: .formula) } label: { Label("Capture", systemImage: "viewfinder") }.help("Capture another formula")
                Button { model.openImage(asFormula: true) } label: { Label("Image…", systemImage: "photo.badge.plus") }
                Divider().frame(height: 20)
                Button { navigate(1) } label: { Image(systemName: "chevron.left") }.disabled(!canNavigate(1))
                Text(position).monospacedDigit().font(.caption).foregroundStyle(.secondary)
                Button { navigate(-1) } label: { Image(systemName: "chevron.right") }.disabled(!canNavigate(-1))
                Spacer()
                Button(action: showHistory) { Label("History", systemImage: "clock.arrow.circlepath") }
                if let id = model.focusedFormulaID { Button { model.editFormula(id) } label: { Label("Edit", systemImage: "square.and.pencil") }.disabled(result?.phase != .ready) }
            }.buttonStyle(.borderless).disabled(model.busy).padding(14).background(.bar)
            Divider()
            HStack {
                Text("Formula").font(.headline)
                Spacer()
                Picker("Preview", selection: $state.previewMode) {
                    ForEach(FormulaPreviewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 260)
            }.padding(.horizontal, 18).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let result, let record {
                        if state.previewMode != .rendered {
                            preview("Original") {
                                if let image = (state.originalID == record.id ? state.original : nil) ?? model.cachedThumbnail(record.id) { Image(nsImage: image).resizable().scaledToFit().padding(8) }
                                else { ProgressView().controlSize(.small) }
                            }
                        }
                        if state.previewMode != .original {
                            preview("Rendered") {
                                if result.phase == .recognising {
                                    VStack(spacing: 10) { ProgressView(); Text("Recognising locally…").font(.callout).foregroundStyle(.black) }
                                } else if let image = result.preview {
                                    Image(nsImage: image).resizable().scaledToFit().padding(12)
                                } else if result.phase == .failed {
                                    VStack(spacing: 10) {
                                        Text(result.error).font(.callout).foregroundStyle(.black).textSelection(.enabled)
                                        Button("Try Again") { model.recogniseSavedFormula(record) }.disabled(model.busy)
                                    }.padding(16)
                                } else if let error = result.previewError {
                                    VStack(spacing: 8) { Text(result.latex).font(.system(.body, design: .monospaced)); Text(error).font(.caption) }
                                        .foregroundStyle(.black).padding(14)
                                } else { ProgressView("Rendering…").foregroundStyle(.black) }
                            }
                        }
                        if result.phase == .ready {
                            if let confidence = result.confidence {
                                HStack(spacing: 10) {
                                    Text("OCR confidence").font(.caption).foregroundStyle(.secondary)
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.secondary.opacity(0.2))
                                            Capsule().fill(confidenceColor(confidence)).frame(width: geometry.size.width * confidence)
                                        }
                                    }.frame(width: 160, height: 7).accessibilityLabel("OCR confidence").accessibilityValue(Text(confidence, format: .percent))
                                    Text(confidence, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit())
                                }.help("Model token confidence, not a verified probability that the entire equation is correct. Compare the original before using it.")
                            } else {
                                Text(result.wasEdited ? "Edited · OCR confidence no longer applies" : "OCR confidence unavailable").font(.caption).foregroundStyle(.secondary)
                            }
                            DisclosureGroup("Recognition details") {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Model: " + result.model)
                                    if let score = result.originalConfidence { Text("Original OCR score: " + score.formatted(.percent.precision(.fractionLength(1)))) }
                                    Text("Original OCR score method: " + (result.confidenceMethod ?? "unavailable"))
                                    if let diagnostics = result.diagnostics {
                                        Text("Original OCR: \(diagnostics.tokenCount) tokens · \(diagnostics.ambiguousTokenCount) below 80% token confidence")
                                        Text("Lowest token score: " + diagnostics.minimumTokenProbability.formatted(.percent.precision(.fractionLength(1))))
                                        Text("Token uncertainty is not a per-symbol error count. Edited output is not rescored.").foregroundStyle(.secondary)
                                    }
                                    if result.wasEdited { Text("Original OCR LaTeX: " + result.originalLatex).textSelection(.enabled) }
                                    Button("Recognise Again") {
                                        model.recogniseSavedFormula(record)
                                    }.disabled(model.busy)
                                }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("Copy format").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            formatRow(.latex, text: result.style.format(result.latex), result: result, id: record.id)
                            formatRow(.markdown, text: LatexCopyStyle.displayDollar.format(result.latex), result: result, id: record.id)
                            formatRow(.keynote, text: result.keynote, result: result, id: record.id)
                            formatRow(.unicode, text: result.unicode, result: result, id: record.id)
                            HStack {
                                if result.format == .latex {
                                    Picker("LaTeX style", selection: Binding(get: { result.style }, set: { model.chooseLatexStyle(record.id, $0) })) {
                                        ForEach(LatexCopyStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }.frame(maxWidth: 300)
                                } else if result.format == .markdown {
                                    Text("Display maths · $$ delimiters on separate lines").font(.caption).foregroundStyle(.secondary)
                                } else if result.format == .keynote {
                                    Text(result.keynoteWarning.isEmpty ? "Keynote: bare maths with compatible matrix environments." : result.keynoteWarning)
                                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                } else { Text(result.warning).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
                        }
                    } else {
                        ContentUnavailableView("Capture a formula", systemImage: "function", description: Text("Capture or open an image to recognise, preview and copy an equation."))
                    }
                }.padding(18)
            }.scrollContentBackground(.hidden)
            Divider()
            HStack {
                Text(model.busy ? model.status : result?.copyStatus ?? "Ready").lineLimit(1)
                Spacer()
                Text("Local · \(sessionRecords.count) session \(sessionRecords.count == 1 ? "result" : "results")").foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 18).padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 660, minHeight: 520)
        .task(id: model.focusedFormulaID) {
            state.original = nil; state.originalID = nil
            guard let record else { return }
            let image = try? await model.thumbnail(record)
            guard !Task.isCancelled, model.focusedFormulaID == record.id else { return }
            state.original = image; state.originalID = record.id
        }
    }
    private func preview<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ZStack { RoundedRectangle(cornerRadius: 10).fill(.white); content() }
                .frame(maxWidth: .infinity).frame(height: state.previewMode == .both ? 150 : 240)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.gray.opacity(0.18)))
        }
    }
    private func formatRow(_ format: OutputFormat, text: String, result: FormulaResult, id: UUID) -> some View {
        HStack(spacing: 10) {
            Text(format.rawValue).font(.system(size: 12, weight: .semibold)).frame(width: 78, alignment: .leading)
            ScrollView(.horizontal) { Text(text.replacingOccurrences(of: "\n", with: " ↵ ")).font(format == .unicode ? Font(model.selectedMathFont.resolvedFont.withSize(16)) : .system(size: 12, design: .monospaced)).lineLimit(1).textSelection(.enabled) }.scrollContentBackground(.hidden).frame(height: format == .unicode ? 24 : 18)
            if format == .unicode && !result.warning.isEmpty { Button { state.showUnicodeWarning.toggle() } label: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                    .buttonStyle(.borderless).help(result.warning).accessibilityLabel("Unicode representation warning: " + result.warning)
                    .onHover { hovering in state.showUnicodeWarning = hovering }
                    .popover(isPresented: $state.showUnicodeWarning, arrowEdge: .bottom) {
                        Text(result.warning).font(.callout).padding(14).frame(width: 300).fixedSize(horizontal: false, vertical: true)
                    } }
            if result.format == format { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            Button { model.chooseFormulaFormat(id, format) } label: { Image(systemName: "doc.on.doc").frame(width: 26, height: 22) }
                .buttonStyle(.borderless).help("Select and copy \(format.rawValue)")
        }.padding(10).background(result.format == format ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).onTapGesture { model.chooseFormulaFormat(id, format) }
    }
    private func confidenceColor(_ value: Double) -> Color {
        // Presentation scale only: red → orange → green, not calibrated accuracy bands.
        let score = min(1, max(0, value))
        if score < 0.8 { return Color(red: 0.95, green: 0.2 + 0.4 * score / 0.8, blue: 0.12) }
        let t = (score - 0.8) / 0.2
        return Color(red: 0.95 - 0.7 * t, green: 0.6 + 0.15 * t, blue: 0.12 + 0.23 * t)
    }
    private var position: String {
        guard let index = sessionRecords.firstIndex(where: { $0.id == model.focusedFormulaID }) else { return "0 / \(sessionRecords.count)" }
        return "\(sessionRecords.count - index) / \(sessionRecords.count)"
    }
    private func canNavigate(_ offset: Int) -> Bool {
        guard let index = sessionRecords.firstIndex(where: { $0.id == model.focusedFormulaID }) else { return false }
        return sessionRecords.indices.contains(index + offset)
    }
    private func navigate(_ offset: Int) {
        guard let index = sessionRecords.firstIndex(where: { $0.id == model.focusedFormulaID }), sessionRecords.indices.contains(index + offset) else { return }
        model.focusedFormulaID = sessionRecords[index + offset].id
    }
}
