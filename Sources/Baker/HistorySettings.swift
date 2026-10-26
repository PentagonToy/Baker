import SwiftUI
import AppKit

struct HistorySettings: View {
    @ObservedObject var model: Workbench
    @Binding var confirmFormulaClear: Bool
    var body: some View {
        BakerSettingsSection(title: "History") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture images").font(BakerTypography.section)
                HStack {
                    Text("Keep latest"); Spacer()
                    HistoryChoicePicker(title: "Maximum images", selection: $model.imageHistoryLimit,
                        options: [(0, "No limit")] + [50, 100, 250, 500, 1000, 5000].map { ($0, "\($0) images") })
                        .frame(width: 170, height: 24)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    HistoryChoicePicker(title: "Image retention", selection: $model.imageHistoryDays,
                        options: [(0, "No age limit")] + [7, 10, 30, 90].map { ($0, "\($0) days") })
                        .frame(width: 170, height: 24)
                }
                Text("Image limits move files to Trash and remove linked results. Videos and GIFs stay.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button("Review & Apply…", action: model.reviewImageRetention)
                Divider().padding(.vertical, 4)
                Text("Formula results").font(BakerTypography.section)
                HStack {
                    Text("Keep latest"); Spacer()
                    HistoryChoicePicker(title: "Maximum results", selection: $model.formulaHistoryLimit,
                        options: [10, 25, 50, 100, 200, 500].map { ($0, "\($0) results") })
                        .frame(width: 170, height: 24)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    HistoryChoicePicker(title: "Formula retention", selection: $model.formulaHistoryDays,
                        options: FormulaHistoryOptions.days.map { ($0, $0 == 0 ? "No age limit" : "\($0) days") })
                        .frame(width: 170, height: 24)
                }
                Text("\(model.savedFormulas.count) saved results. Removing results keeps capture images.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button("Clear Formula History…") { confirmFormulaClear = true }
                    .confirmationDialog("Clear saved formula history?", isPresented: $confirmFormulaClear) {
                        Button("Clear Formula History", role: .destructive, action: model.clearFormulaHistory)
                    } message: { Text("Removes formula text and diagnostics from this Mac. Capture images remain.") }
            }.disabled(model.busy)
        }
    }
}

/// Native popup buttons share actual bezel dimensions rather than an outer alignment frame.
private struct HistoryChoicePicker: NSViewRepresentable {
    let title: String
    @Binding var selection: Int
    let options: [(Int, String)]
    func makeCoordinator() -> Coordinator { Coordinator($selection) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small; button.font = .systemFont(ofSize: 12)
        button.autoenablesItems = false; button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:)); button.setAccessibilityLabel(title)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if button.itemTitles != options.map({ $0.1 }) {
            button.removeAllItems()
            for (value, label) in options { button.addItem(withTitle: label); button.lastItem?.tag = value }
        }
        button.selectItem(withTag: selection); button.isEnabled = context.environment.isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 170, height: 24)
    }
    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(_ selection: Binding<Int>) { self.selection = selection }
        @objc func choose(_ sender: NSPopUpButton) { if let item = sender.selectedItem { selection.wrappedValue = item.tag } }
    }
}
