import AppKit
import BakerCore
import SwiftUI

/// Quick review and copying stay near the menu bar. Detailed editing opens the workspace.
struct FormulaCapturePopover: View {
    @ObservedObject var model: Workbench
    let openWorkspace: () -> Void
    private let formats: [OutputFormat] = [.latex, .markdown, .keynote, .unicode]
    private var result: FormulaResult? { model.focusedFormulaID.flatMap { model.formulaResults[$0] } }
    private var format: OutputFormat { result.map { formats.contains($0.format) ? $0.format : .latex } ?? .latex }
    private var source: String {
        guard let result else { return "" }
        switch format {
        case .unicode: return result.unicode
        case .keynote: return result.keynote
        case .markdown: return LatexCopyStyle.displayDollar.format(result.latex)
        default: return result.style.format(result.latex)
        }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Formula", systemImage: "sum").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: openWorkspace) { Label("Workspace", systemImage: "arrow.up.right") }
                    .buttonStyle(BakerButtonStyle())
                    .help("Review the original, edit LaTeX and browse saved formulas")
            }.frame(height: 32)
            preview.frame(maxWidth: .infinity).frame(height: 128)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.08)))
            Picker("Copy format", selection: Binding(get: { format }, set: { selected in
                guard let id = model.focusedFormulaID else { return }
                model.chooseFormulaFormat(id, selected)
            })) {
                ForEach(formats, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Copy format")
                .disabled(result?.phase != .ready)
            ScrollView {
                Text(source.isEmpty ? (format == .unicode ? "Unicode unavailable. Use LaTeX instead." : "Recognised source appears here.") : source)
                    .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(source.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(10).frame(height: 52)
                .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 10) {
                Button {
                    guard let id = model.focusedFormulaID else { return }; model.copyFormula(id)
                } label: { Label("Copy " + format.rawValue, systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(BakerButtonStyle(prominent: true, expands: true))
                    .disabled(result?.phase != .ready || source.isEmpty)
                Button { model.capture(scrolling: false, action: .formula) } label: {
                    Label("Capture", systemImage: "viewfinder").frame(maxWidth: .infinity)
                }.buttonStyle(BakerButtonStyle(expands: true)).disabled(model.busy)
            }.controlSize(.large)
            HStack(spacing: 12) {
                Text(result?.phase == .ready ? result?.copyStatus ?? "" : "").lineLimit(1).foregroundStyle(BakerTheme.success)
                Spacer(minLength: 0)
                if let result, result.phase == .ready, let score = result.confidence, !result.wasEdited {
                    Text("Model score " + score.formatted(.percent.precision(.fractionLength(0))))
                        .help("Token confidence, not a verified probability that the equation is correct.")
                } else if result?.wasEdited == true { Text("Edited") }
            }.font(BakerTypography.supporting).foregroundStyle(.secondary).frame(height: 18)
        }.padding(16).frame(width: 500, height: 380)
            .labelStyle(BakerToolbarLabelStyle()).font(BakerTypography.body).tint(BakerTheme.accent).background(BakerTheme.background)
    }
    @ViewBuilder private var preview: some View {
        if let result, result.phase == .ready, let image = result.preview {
            Image(nsImage: image).resizable().scaledToFit().padding(16)
        } else if result?.phase == .recognising {
            VStack(spacing: 12) { ProgressView().controlSize(.small); Text("Recognising on this Mac…").foregroundStyle(.secondary) }
        } else if let result, result.phase == .failed {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle").font(.title2)
                Text(result.error).lineLimit(3).multilineTextAlignment(.center)
            }.foregroundStyle(.black.opacity(0.7)).padding(16)
        } else {
            VStack(spacing: 8) {
                Text(result?.latex ?? "").font(.system(.body, design: .serif)).lineLimit(2)
                Text(result?.previewError ?? "Preparing preview…").font(.callout).lineLimit(2)
            }.foregroundStyle(.black.opacity(0.65)).padding(16)
        }
    }
}
