import AppKit
import BakerCore
import SwiftUI

enum SettingsPage: String, CaseIterable {
    case general = "General", capture = "Capture", formula = "Formula", pdf = "PDF", shortcuts = "Shortcuts", menu = "Menu", advanced = "Advanced"
    var symbol: String {
        switch self { case .general: return "gearshape"; case .capture: return "viewfinder"; case .shortcuts: return "command"; case .menu: return "list.bullet"; case .formula: return "sum"; case .pdf: return "doc.richtext"; case .advanced: return "slider.horizontal.3" }
    }
}
extension BakerError.Recovery {
    var settingsPage: SettingsPage? {
        switch self {
        case .formulaSettings: return .formula
        case .pdfSettings: return .pdf
        case .captureSettings: return .capture
        case .advancedSettings: return .advanced
        case .chooseLocation: return .general
        default: return nil
        }
    }
}

@MainActor final class SettingsState: ObservableObject {
    @Published var page: SettingsPage
    @Published var confirmFormulaClear = false
    init(page: SettingsPage = .general) { self.page = page }
}

struct BakerSettings: View {
    @ObservedObject var model: Workbench
    @ObservedObject var shortcuts: CaptureShortcuts
    @StateObject private var state: SettingsState
    init(model: Workbench, shortcuts: CaptureShortcuts, page: SettingsPage = .general, state: SettingsState? = nil) { self.model = model; self.shortcuts = shortcuts; _state = StateObject(wrappedValue: state ?? SettingsState(page: page)); _appearance = AppStorage(PreferenceKeys.appearance, store: model.preferences.defaults) }
    @AppStorage(PreferenceKeys.appearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    Button { state.page = page } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.symbol).frame(width: 18)
                            Text(page.rawValue).lineLimit(1)
                        }.font(BakerTypography.sidebar)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 11)
                            .foregroundStyle(state.page == page ? BakerTheme.selectionForeground : Color.primary)
                            .background(state.page == page ? BakerTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 10) {
                    if let icon = BakerImages.appIcon(dark: colorScheme == .dark) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 36, height: 36) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Baker").font(BakerTypography.section)
                        Text("A keen eye.\nA fresh result.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                        Text("Version " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")).font(BakerTypography.supporting).foregroundStyle(.secondary)
                    }
                }.padding(10)
            }.padding(12).frame(width: 184).background(BakerTheme.sidebar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(state.page.rawValue).font(.title2.weight(.semibold))
                    content
                    Spacer(minLength: 0)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minWidth: 0, maxWidth: .infinity)
        }.onChange(of: appearance) { _ in BakerAppearance.apply(defaults: model.preferences.defaults) }.font(BakerTypography.body).tint(BakerTheme.accent).background(BakerTheme.background).frame(minWidth: 780, minHeight: 560)
    }
    @ViewBuilder private var content: some View {
        switch state.page {
        case .general:
            card("Startup") { LaunchAtLoginSettings(controller: model.launchAtLogin) }
            card("Updates") { AppUpdatesSettings(updates: model.updates) }
            card("Clipboard") {
                toggle("Copy captured images", value: $model.copyCapturedImages)
                Divider()
                toggle("Copy recognised text", value: $model.copyRecognisedText)
                Divider()
                toggle("Open text editor after recognition", value: $model.showResults)
            }
            Text("Formula results always copy the selected format and open in the Formula Workspace.").font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            card("Appearance") {
                HStack {
                    Text("Theme"); Spacer()
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.labelsHidden().frame(width: 160)
                }
            }
            card("Save location") {
                Text(model.storageDirectory.path).font(BakerTypography.body).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                HStack {
                    Button("Choose Folder…", action: model.chooseStorageFolder).disabled(model.busy)
                    Button("Open Folder", action: model.revealCaptures)
                }
            }
            Text("Images, recordings and formula history are saved in this folder. You can choose a synced folder. Existing files stay in their previous location.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            HistorySettings(model: model, confirmFormulaClear: $state.confirmFormulaClear)
            card("Presets") {
                HStack {
                    Button("Save Preset…", action: model.saveSettingsPreset)
                    Button("Load Preset…", action: model.loadSettingsPreset)
                }.disabled(model.busy)
                Text("Portable preferences in the Presets subfolder. Models stay on this Mac.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
        case .capture:
            card("Screen Recording") { ScreenRecordingPermissionView(permission: model.screenRecordingPermission, busy: model.busy, reopen: { model.onReopen?() }) }
            card("Appearance") { toggle("Hide desktop icons in captures and recordings", value: $model.hideDesktopIcons) }
            card("Feedback") { toggle("Capture sounds", value: $model.captureSounds) }
            card("Quick previews") {
                HStack { Text("Visible captures"); Spacer(); Stepper("\(model.visibleCaptures)", value: $model.visibleCaptures, in: 1...5).frame(width: 95) }
            }
            Text("Closing a preview keeps its saved image and formula result.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            OCRLanguageSettings(selection: model.selectedOCRLanguages, setLanguage: model.setOCRLanguage)
        case .shortcuts:
            card("Capture and record") { CaptureShortcutSettings(shortcuts: shortcuts) }
        case .menu:
            MenuLayoutSettings(preferences: model.preferences.defaults)
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
                    Text("Included in Baker. Install through Font Book to retain this font in other apps.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                }
                Text(model.selectedMathFont.installedFont == nil ? "Font unavailable; using \(model.selectedMathFont.resolvedFont.familyName ?? "system font")." : "Ordinary Paste includes this font.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
            card("Preview cache") {
                Button("Clear Preview Cache", action: model.clearPreviewCache).disabled(model.busy)
            }
        case .pdf:
            PDFEngineSetupView(setup: model.pdfEngineSetup, inUse: model.busy)
        case .advanced:
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
            Text(title).font(BakerTypography.section).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14, content: content).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        }
    }
    private func toggle(_ title: String, value: Binding<Bool>) -> some View {
        HStack { Text(title).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 16); Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
    private func path(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title); Spacer(); Button("Choose…") { let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path } } }
            TextField("Not configured", text: value).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced)).frame(minWidth: 0, maxWidth: .infinity).help(value.wrappedValue)
        }
    }
    private func open(_ address: String) { if let url = URL(string: address) { NSWorkspace.shared.open(url) } }
}

@MainActor
enum BakerAppearance {
    static func apply(defaults: UserDefaults = .standard) {
        switch BakerPreferences(defaults: defaults)[PreferenceKeys.appearance] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
