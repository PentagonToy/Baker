import AppKit
import BakerCore
import SwiftUI

enum FormulaCardLayout {
    static let size = NSSize(width: 400, height: 340)
}

struct FormulaResultCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let result: FormulaResult
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Formula", systemImage: "sum").font(BakerTypography.section)
                Spacer()
                if let provider = result.recognitionProvider { RecognitionProviderLabel(provider: provider) }
                if result.phase == .recognising { ProgressView().controlSize(.small) }
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Close preview · keep saved capture")
            }
            Group {
                switch result.phase {
                case .recognising:
                    VStack(spacing: 8) { Text("Recognising equation…").font(BakerTypography.body); Text(result.recognitionMessage).font(BakerTypography.supporting).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Could not recognise this equation", systemImage: "exclamationmark.triangle").font(BakerTypography.body.weight(.medium))
                        ScrollView { Text(result.error).font(BakerTypography.supporting).textSelection(.enabled) }
                        FormulaFailureActions(model: model, record: record, failure: result.failure)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                case .ready:
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(BakerTheme.paper)
                        if let preview = result.preview {
                            Image(nsImage: preview).resizable().scaledToFit().blendMode(colorScheme == .dark ? .normal : .multiply).padding(8)
                        } else if result.previewError != nil {
                            ScrollView { Text(result.latex).font(.system(size: 13, design: .monospaced)).foregroundStyle(.black).textSelection(.enabled).padding(10) }
                        } else { ProgressView("Rendering…").controlSize(.small).foregroundStyle(.black) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if result.format == .unicode {
                        Text(result.unicode).font(Font(model.selectedMathFont.resolvedFont)).textSelection(.enabled).lineLimit(2)
                            .help(result.warning)
                    }
                }
            }.frame(minHeight: 72, maxHeight: .infinity)
            if result.phase == .ready {
                Picker("Copy format", selection: Binding(get: { result.format }, set: { model.chooseFormulaFormat(record.id, $0) })) {
                        Text("LaTeX").tag(OutputFormat.latex)
                        Text("Markdown").tag(OutputFormat.markdown)
                        Text("Keynote").tag(OutputFormat.keynote)
                        Text("Unicode").tag(OutputFormat.unicode)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                    .accessibilityLabel("Copy format").frame(maxWidth: .infinity)
                HStack {
                    if result.format == .latex {
                        Picker("LaTeX style", selection: Binding(get: { result.style }, set: { model.chooseLatexStyle(record.id, $0) })) {
                            ForEach(LatexCopyStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(maxWidth: 220)
                    } else if result.format == .keynote {
                        Text(result.keynoteWarning.isEmpty ? "Keynote LaTeX · no delimiters" : "Check compatibility").font(BakerTypography.supporting).foregroundStyle(.secondary).help(result.keynoteWarning)
                    } else if result.format == .unicode {
                        Text("Editable Unicode · layout approximated").font(BakerTypography.supporting).foregroundStyle(.secondary).help(result.warning)
                    }
                    Spacer(minLength: 0)
                    Button("Edit…") { model.editFormula(record.id) }.buttonStyle(.plain).disabled(model.busy)
                }
                HStack(spacing: 8) {
                    Label(result.copyStatus.isEmpty ? "Ready" : result.copyStatus,
                          systemImage: result.copyStatus.contains("failed") ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Copy") { model.copyFormula(record.id) }
                        .buttonStyle(.borderedProminent).tint(BakerTheme.accent).fixedSize()
                }
            } else {
                Text(result.phase == .recognising ? "The selected format will copy automatically." : "The original capture is saved in history.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
        }
        .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .padding(3)
        .accessibilityElement(children: .contain).accessibilityLabel("Formula result")
    }
}

/// Recovery stays explicit: retry transient errors, prepare models, or choose a new input.
struct FormulaFailureActions: View {
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let failure: BakerError?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let suggestion = failure?.recoverySuggestion { Text(suggestion).font(BakerTypography.supporting) }
            if let page = failure?.recovery.settingsPage {
                Button("Open Settings") { model.onSettingsNeeded?(page) }
            } else if failure?.isRetryable == true {
                Button("Try Again") { model.recogniseSavedFormula(record) }.disabled(model.busy)
            } else {
                Button("Choose Image…") { model.openImage(asFormula: true) }.disabled(model.busy)
            }
        }
    }
}
