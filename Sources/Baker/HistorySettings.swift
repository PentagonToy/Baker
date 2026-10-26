import SwiftUI

struct HistorySettings: View {
    @ObservedObject var model: Workbench
    @Binding var confirmFormulaClear: Bool
    var body: some View {
        BakerSettingsSection(title: "History") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture images").font(BakerTypography.section)
                HStack {
                    Text("Keep latest"); Spacer()
                    Picker("Maximum images", selection: $model.imageHistoryLimit) {
                        Text("No limit").tag(0)
                        ForEach([50, 100, 250, 500, 1000, 5000], id: \.self) { Text("\($0) images").tag($0) }
                    }.labelsHidden().frame(width: 170, alignment: .trailing)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    Picker("Image retention", selection: $model.imageHistoryDays) {
                        Text("No age limit").tag(0)
                        ForEach([7, 10, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
                    }.labelsHidden().frame(width: 170, alignment: .trailing)
                }
                Text("Image limits move files to Trash and remove linked results. Videos and GIFs stay.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button("Review & Apply…", action: model.reviewImageRetention)
                Divider().padding(.vertical, 4)
                Text("Formula results").font(BakerTypography.section)
                HStack {
                    Text("Keep latest"); Spacer()
                    Picker("Maximum results", selection: $model.formulaHistoryLimit) {
                        ForEach([10, 25, 50, 100, 200, 500], id: \.self) { Text("\($0) results").tag($0) }
                    }.labelsHidden().frame(width: 170, alignment: .trailing)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    Picker("Formula retention", selection: $model.formulaHistoryDays) {
                        Text("No age limit").tag(0); Text("10 days").tag(10); Text("30 days").tag(30)
                    }.labelsHidden().frame(width: 170, alignment: .trailing)
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
