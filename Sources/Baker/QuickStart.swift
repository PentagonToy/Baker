import AppKit
import BakerCore
import SwiftUI

/// Presentation progress only. Practice uses the normal capture pipeline.
@MainActor final class QuickStartProgress: ObservableObject {
    enum Step: Int, CaseIterable {
        case formula, workspace, copy, scrolling, recording, everyday
        var title: String { ["Capture a formula", "Formula Workspace", "Copy what you need", "Scrolling capture", "Record a moment", "Keep things close"][rawValue] }
        var symbol: String { ["sum", "rectangle.split.2x1", "doc.on.doc", "scroll", "record.circle", "photo.stack"][rawValue] }
    }
    let preferences: BakerPreferences
    @Published var step: Step { didSet { preferences[PreferenceKeys.quickStartStep] = step.rawValue } }
    @Published var practising = false
    @Published var captured = false
    @Published var practiceID: UUID?
    var presented = false
    init(preferences: BakerPreferences = BakerPreferences()) {
        self.preferences = preferences
        step = Step(rawValue: preferences[PreferenceKeys.quickStartStep]) ?? .formula
    }
    func move(_ offset: Int) { if let next = Step(rawValue: step.rawValue + offset) { step = next } }
    func track(_ id: UUID) { if presented && practising { practiceID = id } }
    func observe(_ values: [UUID: FormulaResult]) {
        guard practising, let id = practiceID, let value = values[id] else { return }
        if value.phase == .ready { captured = true; practising = false }
        else if value.phase == .failed { practising = false }
    }
    func dismiss() { presented = false; practising = false }
}

struct QuickStartActions {
    let capture: () -> Void
    let workspace: () -> Void
    let scrolling: () -> Void
    let recording: () -> Void
    let history: () -> Void
    let settings: (SettingsPage) -> Void
    let close: () -> Void
}

@MainActor private final class QuickStartDraft: ObservableObject {
    @Published var selectedTool = 0
    @Published var selectedFormat = 0
    @Published var copied = false
}

struct QuickStartView: View {
    @ObservedObject var progress: QuickStartProgress
    @ObservedObject var model: Workbench
    @ObservedObject var permission: ScreenRecordingPermission
    @ObservedObject var formulaSetup: FormulaSetup
    let actions: QuickStartActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var draft = QuickStartDraft()
    private let tools = ["Capture", "Image…", "New", "History", "Edit"]
    private let toolDescriptions = ["Capture another equation.", "Open a saved formula image.", "Start with an empty input. Saved formulas stay in History.", "Browse saved formulas. Arrows move between results.", "Correct the LaTeX and refresh the preview."]
    private let formats = ["LaTeX", "Markdown", "Keynote", "Unicode"]
    private var sample: String { [#"x^{2}+2x+1=0"#, #"$$ x^{2}+2x+1=0 $$"#, #"x^{2}+2x+1=0"#, "x² + 2x + 1 = 0"][draft.selectedFormat] }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Quick Start", systemImage: "sparkles").font(.headline).padding(.bottom, 18)
                ForEach(QuickStartProgress.Step.allCases, id: \.self) { step in
                    Button { progress.step = step } label: {
                        HStack(spacing: 9) {
                            Text("\(step.rawValue + 1)").font(.callout.monospacedDigit()).frame(width: 22, height: 22)
                                .background(progress.step == step ? BakerTheme.accent.opacity(0.2) : Color.secondary.opacity(0.08), in: Circle())
                            Text(step.title).font(BakerTypography.sidebar).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }.padding(9).frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
                            .background(progress.step == step ? BakerTheme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityAddTraits(progress.step == step ? .isSelected : [])
                }
                Spacer()
                Text("Skip any step.").font(.callout).foregroundStyle(.secondary)
            }.padding(20).frame(width: 195).background(BakerTheme.sidebar)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(progress.step.rawValue + 1) of \(QuickStartProgress.Step.allCases.count)").monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart") { progress.step = .formula; progress.practising = false; progress.captured = false; progress.practiceID = nil }
                    Button("Skip Tour", action: actions.close).keyboardShortcut(.cancelAction)
                }.font(BakerTypography.supporting).padding(.bottom, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(progress.step.title, systemImage: progress.step.symbol).font(BakerTypography.title)
                        page
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
                }.id(progress.step).transition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: progress.step)
                Divider().padding(.vertical, 16)
                HStack {
                    Button("Back") { progress.move(-1) }.frame(minWidth: 88).disabled(progress.step == .formula)
                    Spacer()
                    Button(progress.step == .everyday ? "Finish" : "Next") {
                        if progress.step == .everyday { actions.close() } else { progress.move(1) }
                    }.buttonStyle(BakerButtonStyle(prominent: progress.step != .formula)).keyboardShortcut(.defaultAction)
                }
            }.padding(26).frame(maxWidth: .infinity)
        }.frame(minWidth: 760, minHeight: 610).background(BakerTheme.background).tint(BakerTheme.accent)
            .font(BakerTypography.body).buttonStyle(BakerButtonStyle())
            .onReceive(model.$formulaResults) { progress.observe($0) }
            .onAppear(perform: permission.refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permission.refresh() }
            .onChange(of: draft.selectedFormat) { _ in draft.copied = false }
    }
    @ViewBuilder private var page: some View {
        switch progress.step {
        case .formula:
            captureAccess
            if permission.allowed { formulaPreparation }
            detail("Choose Formula in the menu bar. Drag around this equation or your own.")
            Text("x² + 2x + 1 = 0").font(.custom("Latin Modern Math", size: 34)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 90).background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Practice equation: x squared plus two x plus one equals zero")
            if permission.allowed && formulaSetup.ready {
                Button(progress.captured ? "Capture Another Formula" : "Try Formula Capture") {
                    progress.practising = true; progress.practiceID = nil; actions.capture()
                }.buttonStyle(BakerButtonStyle(prominent: true, expands: true)).frame(width: 220).disabled(model.busy)
            }
            if progress.captured {
                Label("You captured a formula", systemImage: "checkmark.circle.fill").foregroundStyle(BakerTheme.accent)
            } else if model.busy {
                detail(model.status)
            }
            detail("The result appears below Baker’s icon. Practice saves a capture and copies its result. Esc cancels.")
        case .workspace:
            detail("Review the original, preview and source together. Select a button below to learn what it does.")
            HStack(spacing: 8) {
                ForEach(Array(tools.enumerated()), id: \.offset) { index, title in
                    Button(title) { draft.selectedTool = index }.buttonStyle(BakerButtonStyle(prominent: draft.selectedTool == index, expands: true))
                        .accessibilityAddTraits(draft.selectedTool == index ? .isSelected : [])
                }
            }
            Text(toolDescriptions[draft.selectedTool]).frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            note("Original · Rendered · Both", "Compare the image and preview. Model score does not guarantee accuracy.")
            Button("Open Formula Workspace", action: actions.workspace)
                .buttonStyle(BakerButtonStyle(expands: true)).frame(width: 220).disabled(model.busy)
            detail("Return to this guide when ready.")
        case .copy:
            detail("Choose a format your destination accepts.")
            Picker("Copy format", selection: $draft.selectedFormat) { ForEach(0..<formats.count, id: \.self) { Text(formats[$0]).tag($0) } }.pickerStyle(.segmented)
            Text(sample).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(18)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            detail(["Use LaTeX in a maths editor.", "Markdown wraps the formula in display-maths delimiters.", "In Keynote, paste through Insert → Equation.", "Plain text. Complex expressions may be simplified or empty."][draft.selectedFormat])
            Button(draft.copied ? "Sample Copied" : "Copy Sample") {
                NSPasteboard.general.clearContents(); draft.copied = NSPasteboard.general.setString(sample, forType: .string)
            }.buttonStyle(BakerButtonStyle(expands: true)).frame(width: 220)
            detail("Copy Sample changes only your clipboard.")
        case .scrolling:
            detail("Select moving content only. Leave fixed headers and scrollbars outside.")
            note("Scroll slowly yourself", "Scroll slowly, pause, then choose Finish. Cancel discards the capture.")
            captureReminder
            Button("Try Scrolling Capture", action: actions.scrolling)
                .buttonStyle(BakerButtonStyle(expands: true)).frame(width: 220).disabled(model.busy || !permission.allowed)
            Divider()
            note("Area · All · Window", "Select a rectangle, capture a display or pick one window.")
            note("Repeat Area", "Capture the same region again. Select again after display changes.")
        case .recording:
            detail("Choose Record…, select a region, then pick Video or GIF.")
            note("Video", "Up to 3 minutes. Optional app audio, without microphone recording.")
            note("GIF", "Silent animation, up to 30 seconds. Show cursor is optional.")
            note("You choose when to start", "Press Record to begin. Press the square Stop button to save.")
            captureReminder
            Button("Open Recording Setup", action: actions.recording)
                .buttonStyle(BakerButtonStyle(expands: true)).frame(width: 220).disabled(model.busy || !permission.allowed)
            detail("Setup selects a region. It does not start recording.")
        case .everyday:
            note("Edit a capture", "Click a thumbnail for annotation, background removal or tracing. Undo before Done. Done replaces the file.")
            note("Capture History", "Browse images, formulas, videos and GIFs. SVG files open as previews.")
            note("Text · Open Files", "Text copies words. Open Files recognises images and converts PDFs.")
            note("Offline PDF conversion", "Download the Offline Model in Advanced for PDF conversion only.")
            HStack(spacing: 8) {
                Button("History", action: actions.history).disabled(model.busy)
                Button("Offline Model") { actions.settings(.advanced) }
                Button("Shortcuts") { actions.settings(.shortcuts) }
            }.buttonStyle(BakerButtonStyle(expands: true))
            detail("Reorder commands in Settings → Menu. Quick Start is always available from Baker’s menu.")
        }
    }
    private var formulaPreparation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Formula model").font(.headline)
                Spacer()
                Picker("Formula model", selection: Binding(get: { formulaSetup.engine }, set: { formulaSetup.select($0) })) {
                    ForEach(FormulaEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 200).disabled(formulaSetup.working || model.busy)
            }
            if formulaSetup.ready {
                Label("Ready for formula capture", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(BakerTheme.accent)
            } else if formulaSetup.working {
                ProgressView(value: formulaSetup.progress)
                HStack {
                    Text(formulaSetup.message).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: formulaSetup.cancel)
                }
            } else {
                detail("Download one model. Recognition then works offline.")
                Button("Download · " + formulaSetup.downloadSize, action: formulaSetup.prepare)
                    .buttonStyle(BakerButtonStyle(prominent: true, expands: true))
                    .frame(width: 220).disabled(model.busy || !formulaSetup.runtimeAvailable)
                if formulaSetup.failure != nil { detail(formulaSetup.message) }
            }
        }.padding(16).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.border))
    }
    @ViewBuilder private var captureAccess: some View {
        if permission.allowed {
            Label("Screen recording access is ready", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(BakerTheme.accent)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Allow screen recording", systemImage: "lock.rectangle").font(.headline)
                detail("Enable Baker in System Settings. Reopen if macOS asks. This guide will resume.")
                HStack(spacing: 8) {
                    Button("Allow Access…") {
                        model.preferences[PreferenceKeys.resumeQuickStart] = true
                        permission.request()
                    }.buttonStyle(BakerButtonStyle(prominent: true, expands: true))
                    Button("System Settings") {
                        model.preferences[PreferenceKeys.resumeQuickStart] = true
                        permission.openSettings()
                    }
                }
                HStack(spacing: 8) {
                    Button("Check Again", action: permission.refresh)
                    Button("Reopen Baker") {
                        model.preferences[PreferenceKeys.resumeQuickStart] = true
                        model.onReopen?()
                    }.disabled(model.busy)
                }
            }.buttonStyle(BakerButtonStyle(expands: true))
                .padding(16).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    @ViewBuilder private var captureReminder: some View {
        if !permission.allowed {
            HStack(spacing: 12) {
                Label("Screen recording access needed", systemImage: "lock.rectangle")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Set Up…") { progress.step = .formula }
            }.padding(12).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func detail(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
    }
    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); detail(text) }
    }
}
