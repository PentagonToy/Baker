import BakerCore
import SwiftUI

struct OCRLanguageSettings: View {
    let selection: [String]
    let setLanguage: (String, Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text recognition languages").font(BakerTypography.section).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Active languages"); Spacer(); Text("\(selection.count) / \(OCRLanguages.maximumActive)").foregroundStyle(.secondary) }
                ForEach(OCRLanguages.choices, id: \.0) { code, name in
                    let selected = selection.contains(code)
                    Toggle(name, isOn: Binding(get: { selection.contains(code) }, set: { setLanguage(code, $0) }))
                        .disabled((!selected && selection.count >= OCRLanguages.maximumActive) || (selected && selection.count == 1))
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 13))

        }
    }
}
