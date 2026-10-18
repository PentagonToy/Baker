import SwiftUI

struct HistorySettings: View {
    @ObservedObject var model: Workbench
    @Binding var confirmFormulaClear: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History").font(BakerTypography.section).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Text("Capture images").font(BakerTypography.section)
                HStack {
                    Text("Keep latest"); Spacer()
                    Picker("Maximum images", selection: $model.imageHistoryLimit) {
                        Text("No limit").tag(0)
                        ForEach([50, 100, 250, 500, 1000, 5000], id: \.self) { Text("\($0) images").tag($0) }
                    }.labelsHidden().frame(width: 170)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    Picker("Image retention", selection: $model.imageHistoryDays) {
                        Text("No age limit").tag(0)
                        ForEach([7, 10, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
                    }.labelsHidden().frame(width: 170)
                }
                Text("Limits move images to Trash and remove linked formula results. Videos and GIFs remain.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                HStack {
                    Button("Review & Apply…", action: model.reviewImageRetention)
                    Button("Clear Image Cache", action: model.clearImageCache)
                }
                Text("Clearing the cache also removes history entries whose files were deleted in Finder.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Divider().padding(.vertical, 4)
                Text("Formula results").font(BakerTypography.section)
                HStack {
                    Text("Keep latest"); Spacer()
                    Picker("Maximum results", selection: $model.formulaHistoryLimit) {
                        ForEach([10, 25, 50, 100, 200, 500], id: \.self) { Text("\($0) results").tag($0) }
                    }.labelsHidden().frame(width: 170)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    Picker("Formula retention", selection: $model.formulaHistoryDays) {
                        Text("No age limit").tag(0); Text("10 days").tag(10); Text("30 days").tag(30)
                    }.labelsHidden().frame(width: 170)
                }
                Text("\(model.savedFormulas.count) saved results. Limits remove formula text and diagnostics; capture images remain.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button("Clear Formula History…") { confirmFormulaClear = true }
                    .confirmationDialog("Clear saved formula history?", isPresented: $confirmFormulaClear) {
                        Button("Clear Formula History", role: .destructive, action: model.clearFormulaHistory)
                    } message: { Text("Removes formula text and diagnostics from this Mac. Capture images remain.") }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                .disabled(model.busy)
        }
    }
}
