import AppKit
import BakerCore
import SwiftUI

struct FormulaResultCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: Workbench
    let record: CaptureRecord
    let result: FormulaResult
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Formula", systemImage: "function").font(.system(size: 12, weight: .semibold))
                Spacer()
                if result.phase == .recognising { ProgressView().controlSize(.small) }
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Close preview · keep saved capture")
            }
            Group {
                switch result.phase {
                case .recognising:
                    VStack(spacing: 8) { Text("Recognising equation…").font(.callout); Text("Local processing").font(.caption).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Could not recognise this equation", systemImage: "exclamationmark.triangle").font(.callout.weight(.medium))
                        ScrollView { Text(result.error).font(.caption).textSelection(.enabled) }
                        Button("Try Again") { model.selectCapture(record, action: .formula) }.disabled(model.busy)
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
            }
            if result.phase == .ready {
                HStack(spacing: 10) {
                    Picker("Copy format", selection: Binding(get: { result.format }, set: { model.chooseFormulaFormat(record.id, $0) })) {
                        Text("LaTeX").tag(OutputFormat.latex)
                        Text("Markdown").tag(OutputFormat.markdown)
                        Text("Keynote").tag(OutputFormat.keynote)
                        Text("Unicode").tag(OutputFormat.unicode)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
                    Spacer(minLength: 0)
                    Button("Copy") { model.copyFormula(record.id) }.buttonStyle(.borderedProminent).tint(.orange)
                }
                HStack {
                    if result.format == .latex {
                        Picker("LaTeX style", selection: Binding(get: { result.style }, set: { model.chooseLatexStyle(record.id, $0) })) {
                            ForEach(LatexCopyStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(maxWidth: 220)
                    } else if result.format == .keynote {
                        Text(result.keynoteWarning.isEmpty ? "Keynote LaTeX · no delimiters" : "Check compatibility").font(.caption2).foregroundStyle(.secondary).help(result.keynoteWarning)
                    } else {
                        Text("Editable Unicode · layout approximated").font(.caption2).foregroundStyle(.secondary).help(result.warning)
                    }
                    Spacer(minLength: 0)
                    Button("Edit…") { model.editFormula(record.id) }.buttonStyle(.plain).disabled(model.busy)
                }
                HStack(spacing: 4) {
                    Image(systemName: result.copyStatus.contains("failed") ? "exclamationmark.circle" : "checkmark.circle.fill")
                    Text(result.copyStatus.isEmpty ? "Ready" : result.copyStatus)
                    Spacer()
                    if result.previewError != nil { Text("Source preview").help(result.previewError ?? "") }
                }.font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(result.phase == .recognising ? "The selected format will copy automatically." : "The original capture is saved in history.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        .padding(3)
        .accessibilityElement(children: .contain).accessibilityLabel("Formula result")
    }
}
