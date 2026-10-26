import Foundation
import SwiftUI

/// Local completion counters only; no account, credentials or network monitor.
@MainActor final class LocalUsage: ObservableObject {
    struct Counts: Codable {
        var localImages = 0, localDocuments = 0, localPages = 0
        var since = Date()
    }
    @Published private(set) var counts: Counts
    private let defaults: UserDefaults
    init(defaults: UserDefaults) {
        self.defaults = defaults
        counts = defaults.data(forKey: PreferenceKeys.recognitionUsage.name)
            .flatMap { try? JSONDecoder().decode(Counts.self, from: $0) } ?? Counts()
        save()
    }
    func record(pages: Int? = nil) {
        if let pages { counts.localDocuments += 1; counts.localPages += max(0, pages) }
        else { counts.localImages += 1 }
        save()
    }
    func reset() { counts = Counts(); save() }
    private func save() {
        if let data = try? JSONEncoder().encode(counts) { defaults.set(data, forKey: PreferenceKeys.recognitionUsage.name) }
    }
}

@MainActor private final class UsageSettingsState: ObservableObject {
    @Published var confirmReset = false
}
struct LocalUsageSettings: View {
    @ObservedObject var usage: LocalUsage
    let busy: Bool
    @StateObject private var state = UsageSettingsState()
    var body: some View {
        BakerSettingsSection {
            HStack {
                Text("Usage").font(BakerTypography.section)
                RecognitionProviderLabel(provider: "Baker · Local")
                Spacer()
                Text("Since " + usage.counts.since.formatted(date: .abbreviated, time: .omitted))
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button("Reset…") { state.confirmReset = true }.disabled(busy).accessibilityLabel("Reset usage")
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                row("Images", usage.counts.localImages)
                row("PDFs", usage.counts.localDocuments)
                row("PDF pages", usage.counts.localPages)
            }
            Text("Completed on this Mac. Images include text and formula recognition.")
                .font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.alert("Reset usage?", isPresented: $state.confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Usage", role: .destructive, action: usage.reset)
        } message: { Text("Clear local counts and start again from today. Saved captures and results remain.") }
    }
    private func row(_ title: String, _ value: Int) -> some View {
        GridRow { Text(title); Text(value.formatted()).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing) }
    }
}
