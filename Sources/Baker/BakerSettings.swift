import AppKit
import BakerCore
import SwiftUI

enum SettingsPage: String, CaseIterable {
    case general = "General", capture = "Capture", formula = "Formula", cloud = "Cloud", advanced = "Advanced"
    var symbol: String {
        switch self { case .general: return "gearshape"; case .capture: return "viewfinder"; case .formula: return "function"; case .cloud: return "cloud"; case .advanced: return "slider.horizontal.3" }
    }
}
@MainActor private final class SettingsState: ObservableObject { @Published var page = SettingsPage.general; @Published var confirmFormulaClear = false }

struct BakerSettings: View {
    @ObservedObject var model: Workbench
    @ObservedObject private var state = SettingsState()
    init(model: Workbench, page: SettingsPage = .general) { self.model = model; state.page = page }
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    Button { state.page = page } label: {
                        Label(page.rawValue, systemImage: page.symbol).font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                            .foregroundStyle(state.page == page ? Color.white : Color.primary)
                            .background(state.page == page ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 10) {
                    if let icon = BakerImages.appIcon(dark: colorScheme == .dark) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 36, height: 36) }
                    VStack(alignment: .leading) { Text("Baker").font(.headline); Text("Local first").font(.caption).foregroundStyle(.secondary) }
                }.padding(10)
            }.padding(12).frame(width: 170).background(.bar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(state.page.rawValue).font(.title2.weight(.semibold))
                    content
                    Spacer(minLength: 0)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minWidth: 0, maxWidth: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor)).frame(minWidth: 780, minHeight: 560)
    }
    @ViewBuilder private var content: some View {
        switch state.page {
        case .general:
            card("Clipboard") {
                toggle("Copy captured images", value: $model.copyCapturedImages)
                Divider()
                toggle("Copy recognised text", value: $model.copyRecognisedText)
                Divider()
                toggle("Open text editor after recognition", value: $model.showResults)
            }
            Text("Formula results always copy the selected format and open in the Formula Workspace.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .capture:
            card("Feedback") { toggle("Capture sounds", value: $model.captureSounds) }
            card("Quick previews") {
                HStack { Text("Visible captures"); Spacer(); Stepper("\(model.visibleCaptures)", value: $model.visibleCaptures, in: 1...5).frame(width: 95) }
                Divider()
                HStack { Text("Capture history"); Spacer(); Button("Open Folder", action: model.revealCaptures) }
            }
            Text("Closing a preview keeps its saved image and formula result.").font(.caption).foregroundStyle(.secondary)
        case .formula:
            FormulaSetupView(setup: model.formulaSetup).disabled(model.busy)
            card("Unicode maths") {
                HStack {
                    Text("Font"); Spacer()
                    Picker("Font", selection: $model.mathFont) { ForEach(MathFont.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden().frame(width: 210)
                }
                Divider()
                Text("𝑥² + 𝛼𝑥 + ½ = 0").font(Font(model.selectedMathFont.resolvedFont)).padding(.vertical, 12)
                if let url = model.selectedMathFont.bundledFontURL {
                    Button("Install for Other Apps…") { NSWorkspace.shared.open(url) }.help("Open Font Book to install this font for Keynote and other apps")
                    Text("Included in Baker. Install through Font Book to retain this font in other apps.").font(.caption).foregroundStyle(.secondary)
                }
                Text(model.selectedMathFont.installedFont == nil ? "Font unavailable; using \(model.selectedMathFont.resolvedFont.familyName ?? "system font")." : "Ordinary Paste includes this font.").font(.caption).foregroundStyle(.secondary)
            }
            card("Formula history") {
                HStack {
                    Text("Keep latest"); Spacer()
                    Picker("Maximum results", selection: $model.formulaHistoryLimit) { ForEach([10, 25, 50, 100, 200, 500], id: \.self) { Text("\($0) results").tag($0) } }.labelsHidden().frame(width: 160)
                }
                HStack {
                    Text("Keep for"); Spacer()
                    Picker("Retention", selection: $model.formulaHistoryDays) { Text("No age limit").tag(0); Text("10 days").tag(10); Text("30 days").tag(30) }.labelsHidden().frame(width: 160)
                }
                Text("\(model.savedFormulas.count) saved results. Limits remove formula text and diagnostics; capture images and cloud files remain.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Clear Preview Cache", action: model.clearPreviewCache)
                    Button("Clear Formula History…") { state.confirmFormulaClear = true }
                        .confirmationDialog("Clear saved formula history?", isPresented: $state.confirmFormulaClear) {
                            Button("Clear Formula History", role: .destructive, action: model.clearFormulaHistory)
                        } message: { Text("Removes formula text and diagnostics from this Mac. Capture images and cloud copies remain.") }
                }.disabled(model.busy)
            }
        case .cloud:
            GoogleDriveSettings(model: model, drive: model.googleDrive)
            DropboxSettings(model: model, dropbox: model.dropbox)
        case .advanced:
            card("Text recognition languages") {
                HStack { Text("Active languages"); Spacer(); Text("\(model.selectedOCRLanguages.count) / 3").foregroundStyle(.secondary) }
                ForEach(OCRLanguages.choices, id: \.0) { code, name in
                    let selected = model.selectedOCRLanguages.contains(code)
                    Toggle(name, isOn: Binding(get: { model.selectedOCRLanguages.contains(code) }, set: { model.setOCRLanguage(code, enabled: $0) }))
                        .disabled((!selected && model.selectedOCRLanguages.count >= 3) || (selected && model.selectedOCRLanguages.count == 1) || (!model.finnishTextMode && code != "fi-FI" && !OCRLanguages.supported.contains(code)))
                }
                Text("Choose 1–3 languages used in the capture. Fewer relevant languages may reduce ambiguity; the limit does not guarantee accuracy.").font(.caption).foregroundStyle(.secondary)
                if model.finnishTextMode {
                    Text("Finnish selected: Tesseract recognises the selected languages for text captures and scanned PDFs. Formula OCR remains separate.").font(.caption).foregroundStyle(.secondary)
                    Text("The text recognition engine and language models are included in Baker.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Text captures and scanned PDFs use Apple Vision. Formula OCR remains separate.").font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Developer overrides") {
                toggle("Use external OCR runtimes", value: $model.developerRuntimeOverrides)
                if model.developerRuntimeOverrides {
                    path("Python executable", value: $model.python)
                    path("Model configuration", value: $model.config)
                    path("Tesseract executable", value: $model.tesseractExecutable)
                }
            }

        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14, content: content).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        }
    }
    private func toggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack { Text(title).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 16); Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
    private func path(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title); Spacer(); Button("Choose…") { let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path } } }
            TextField("Not configured", text: value).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)).frame(minWidth: 0, maxWidth: .infinity).help(value.wrappedValue)
        }
    }
    private func open(_ address: String) { if let url = URL(string: address) { NSWorkspace.shared.open(url) } }
}
