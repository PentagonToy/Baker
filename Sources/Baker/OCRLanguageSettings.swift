import BakerCore
import SwiftUI

struct OCRLanguageSettings: View {
    let selection: [String]
    let setLanguage: (String, Bool) -> Void
    var body: some View {
        BakerSettingsSection {
            HStack {
                Text("Text languages").font(BakerTypography.section)
                Spacer()
                Text("\(selection.count) of \(OCRLanguages.maximumActive) selected").font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(OCRLanguages.choices, id: \.0) { code, name in
                    let selected = selection.contains(code)
                    Toggle(isOn: Binding(get: { selection.contains(code) }, set: { setLanguage(code, $0) })) {
                        Text(name).fixedSize(horizontal: false, vertical: true)
                    }.toggleStyle(.checkbox).frame(minHeight: 24)
                        .disabled((!selected && selection.count >= OCRLanguages.maximumActive) || (selected && selection.count == 1))
                }
            }
        }
    }
}
