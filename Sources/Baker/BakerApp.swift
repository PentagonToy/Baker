import AppKit
import BakerCore
import Combine
import SwiftUI

@main
@MainActor
struct BakerApp {
    static func main() {
        let application = NSApplication.shared
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); return
        }
        let delegate = BakerDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class BakerDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = Workbench()
    private let shortcuts = CaptureShortcuts()
    private var statusItem: NSStatusItem!
    private lazy var overlays = CaptureOverlayController(model: model)
    private let windows = WorkspaceWindows()
    private let settingsState = SettingsState()
    private var subscriptions: Set<AnyCancellable> = []
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onReopen = { [weak self] in self?.reopen() }
        BakerAppearance.apply()
        LegacyCloudCleanup.run()
        model.canChangeStorage = { [weak self] in self?.overlays.hasOpenEditors != true }
        model.onStorageChanged = { [weak self] in
            self?.overlays.resetStorage()
            self?.windows.hide(.formula, .result)
        }
        shortcuts.perform = { [weak self] action in
            guard let self, !self.model.busy else { return }
            switch action {
            case "area": self.captureRegion()
            case "all": self.captureAll()
            case "repeat": self.repeatCaptureArea()
            case "scroll": self.captureScroll()
            case "text": self.captureText()
            case "formula": self.captureFormula()
            case "video": self.recordVideo()
            case "gif": self.recordGIF()
            default: break
            }
        }
        model.onFormulaSetupNeeded = { [weak self] in self?.openSettings(.formula) }
        model.onSettingsNeeded = { [weak self] page in self?.openSettings(page) }
        model.onOpenFiles = { [weak self] format in self?.showFiles(format) }
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = BakerImages.template("baker_menubar_icon", folder: "BakerIcons", fallback: "viewfinder")
        statusItem.button?.toolTip = "Baker · Local capture and OCR"
        statusItem.button?.setAccessibilityLabel("Baker")
        let menu = NSMenu(title: "Baker")
        menu.delegate = self
        statusItem.menu = menu
        model.onImageReady = { [weak self] in
            guard let self, !self.model.formulaCapturePending else { return }
            self.showPreview()
        }
        model.onEditResult = { [weak self] in self?.showResult() }
        model.onFormulaReady = { [weak self] id in
            guard let self, let record = self.model.captures.first(where: { $0.id == id }) else { return }
            self.overlays.dismiss(record.id)
            self.model.focusedFormulaID = id
            self.model.formulaInputPending = false
            self.showFormulaWorkspace()
        }
        model.onResultReady = { [weak self] in
            if self?.model.showResults == true { self?.showResult() }
        }
        model.onCaptureVisibility = { [weak self] visible in
            guard let self else { return }
            self.overlays.setVisible(visible)
        }
        model.onExportReady = { [weak self] in self?.showExport() }
        if !model.preferences[PreferenceKeys.hasShownRecognitionSetup] {
            model.preferences[PreferenceKeys.hasShownRecognitionSetup] = true
            openSettings(.formula)
        }
        model.$problem.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] message in
            self?.model.playCaptureFeedback(success: false)
            let alert = NSAlert(); alert.messageText = "Baker"; alert.informativeText = message
            let failure = self?.model.failure
            if let suggestion = failure?.recoverySuggestion, !message.contains(suggestion) { alert.informativeText += "\n\n" + suggestion }
            let page = failure?.recovery.settingsPage
            let permissions = failure?.recovery == .systemPermissions
            if permissions {
                alert.addButton(withTitle: "Open System Settings"); alert.addButton(withTitle: "Not Now")
            } else {
                alert.addButton(withTitle: "OK")
                if page != nil { alert.addButton(withTitle: "Open Settings") }
            }
            NSApp.activate(ignoringOtherApps: true)
            let choice = alert.runModal()
            if permissions, choice == .alertFirstButtonReturn { self?.model.screenRecordingPermission.openSettings() }
            else if choice == .alertSecondButtonReturn, let page { self?.openSettings(page) }
            self?.model.problem = nil
        }.store(in: &subscriptions)
        rebuildMenu(menu)
        model.warmCaptureSelection()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.terminating, !self.model.busy else { return }
            self.model.launchAtLogin.presentFirstLaunchOffer()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopening a menu-bar utility must not create an unrelated result window.
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task { [model] in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { windows.closeAll(); model.cleanup() }
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    private func installApplicationMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title); root.submenu = menu; main.addItem(root)
            return menu
        }
        func command(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String,
                     target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            entry.target = target; entry.keyEquivalentModifierMask = modifiers; menu.addItem(entry)
        }
        let application = submenu("Baker")
        command(application, "Settings…", #selector(showSettings), ",", target: self)
        application.addItem(.separator())
        command(application, "Hide Baker", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        command(application, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", target: NSApp, modifiers: [.command, .option])
        command(application, "Show All", #selector(NSApplication.unhideAllApplications(_:)), "", target: NSApp)
        application.addItem(.separator())
        command(application, "Quit Baker", #selector(quit), "q", target: self)
        let edit = submenu("Edit")
        command(edit, "Undo", Selector(("undo:")), "z")
        command(edit, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            command(edit, title, Selector(action), key)
        }
        let window = submenu("Window")
        command(window, "Close", #selector(NSWindow.performClose(_:)), "w")
        command(window, "Minimise", #selector(NSWindow.performMiniaturize(_:)), "m")
        NSApp.mainMenu = main; NSApp.windowsMenu = window
    }

    private func applyMenuLayout(_ menu: NSMenu) {
        let layout = BakerMenuLayout.load()
        var sections: [String: [NSMenuItem]] = [:]
        var section: String?
        var pinned: [NSMenuItem] = []
        for entry in menu.items {
            if entry.isSeparatorItem { section = nil; continue }
            if let group = BakerMenuGroup.all.first(where: { $0.title.uppercased() == entry.title }) {
                section = group.id; continue
            }
            if let section { sections[section, default: []].append(entry) }
            else { pinned.append(entry) }
        }
        menu.removeAllItems()
        for group in layout.orderedGroups {
            let source = sections[group.id] ?? []
            let known = Set(group.entries.map(\.id))
            let commands = layout.orderedEntries(group).compactMap { id -> NSMenuItem? in
                guard !layout.hidden.contains(id) else { return nil }
                return source.first { $0.action.map(NSStringFromSelector) == id }
            }
            let activeControls = source.filter { entry in
                guard let action = entry.action else { return false }
                return !known.contains(NSStringFromSelector(action))
            }
            guard !commands.isEmpty || !activeControls.isEmpty else { continue }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(heading(group.title.uppercased()))
            for entry in commands + activeControls { menu.addItem(entry) }
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for entry in pinned { menu.addItem(entry) }
    }

    private func item(_ title: String, _ action: Selector, symbol: String, custom: String? = nil, enabled: Bool = true, key: String = "", shortcut: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.isEnabled = enabled
        if let shortcut, let binding = shortcuts.bindings[shortcut] {
            item.keyEquivalent = binding.menuKey
            item.keyEquivalentModifierMask = binding.menuModifiers
        }
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        item.image = custom.map { BakerImages.template($0, fallback: symbol) } ?? BakerImages.system(symbol)
        return item
    }
    private func heading(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        return item
    }
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems(); menu.autoenablesItems = false
        menu.showsStateColumn = true
        menu.addItem(heading("CAPTURE"))
        menu.addItem(item("All", #selector(captureAll), symbol: "display", custom: "capture-all", enabled: !model.busy, shortcut: "all"))
        menu.addItem(item("Area", #selector(captureRegion), symbol: "viewfinder", custom: "capture-area", enabled: !model.busy, shortcut: "area"))
        menu.addItem(item("Repeat Area", #selector(repeatCaptureArea), symbol: "arrow.clockwise", custom: "capture-repeat", enabled: !model.busy && model.canRepeatArea, shortcut: "repeat"))
        menu.addItem(item("Scrolling", #selector(captureScroll), symbol: "scroll", custom: "capture-scroll", enabled: !model.busy, shortcut: "scroll"))
        menu.addItem(item("Text", #selector(captureText), symbol: "text.viewfinder", custom: "capture-text", enabled: !model.busy, shortcut: "text"))
        menu.addItem(item("Formula", #selector(captureFormula), symbol: "sum", custom: "capture-formula", enabled: !model.busy, shortcut: "formula"))
        menu.addItem(item("Record…", #selector(recordScreen), symbol: "record.circle", custom: "record-video", enabled: !model.busy, shortcut: "video"))
        if model.isRecording {
            menu.addItem(item("Stop Recording", #selector(stopRecording), symbol: "stop.circle.fill"))
        }
        menu.addItem(.separator()); menu.addItem(heading("CLIPBOARD & FILES"))
        menu.addItem(item("Open Files", #selector(openImage), symbol: "folder", custom: "files-open", enabled: !model.busy))
        menu.addItem(item("Formula Workspace", #selector(newFormulaWorkspace), symbol: "sum"))
        menu.addItem(item("Open Clipboard Image", #selector(pasteImage), symbol: "clipboard", custom: "clipboard-image", enabled: !model.busy))
        menu.addItem(item("Read Clipboard Text", #selector(readClipboard), symbol: "text.viewfinder", custom: "clipboard-text", enabled: !model.busy))
        if model.busy && !model.isRecording {
            menu.addItem(item("Cancel Processing", #selector(cancelJob), symbol: "xmark.circle"))
        }
        menu.addItem(.separator()); menu.addItem(heading("RECENT"))
        menu.addItem(item("Last Capture", #selector(showPreview), symbol: "photo", enabled: !model.captures.isEmpty))
        menu.addItem(item("Capture History", #selector(showHistory), symbol: "photo.stack", custom: "capture-history"))
        menu.addItem(item("Open Capture Folder", #selector(openCaptureFolder), symbol: "folder", custom: "files-open"))

        menu.addItem(item("Last Result", #selector(showResult), symbol: "doc.text", enabled: !model.output.isEmpty && !model.busy))
        menu.addItem(item("Last Export", #selector(showExport), symbol: "doc", enabled: model.exportURL != nil || model.isConvertingPDF))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), symbol: "gearshape", custom: "settings", key: ","))
        menu.addItem(item("Quit Baker", #selector(quit), symbol: "power", key: "q"))
        applyMenuLayout(menu)
    }
    // Start in the normal run-loop mode after AppKit finishes menu tracking.
    // Global shortcuts use the same path; other applications' menus are untouched.
    private func startCapture(scrolling: Bool = false, action: CaptureAction = .image, fullScreen: Bool = false, reuseArea: Bool = false) {
        statusItem.menu?.cancelTracking()
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.model.capture(scrolling: scrolling, action: action, fullScreen: fullScreen, reuseArea: reuseArea) }
        }
    }
    @objc private func captureRegion() { startCapture() }
    @objc private func repeatCaptureArea() { startCapture(reuseArea: true) }
    @objc private func captureAll() { startCapture(fullScreen: true) }
    @objc private func captureScroll() { startCapture(scrolling: true) }
    @objc private func captureText() { startCapture(action: .text) }
    @objc private func captureFormula() { startCapture(action: .formula) }
    @objc private func captureUnicode() { startCapture(action: .unicode) }
    private func showFiles(_ format: PDFExportFormat? = nil) {
        if let format { model.filesInbox.pdfFormat = format }
        let window = windows.resolve(.files) {
            let panel = FilesWorkspaceWindow()
            panel.title = "Baker · Clipboard & Files"
            panel.contentView = NSHostingView(rootView: FilesWorkspace(model: model, inbox: model.filesInbox))
            return panel
        }
        model.filesInbox.presentationWindow = window
        windows.show(.files)
    }
    @objc private func openImage() { showFiles() }
    @objc private func pasteImage() { model.pasteImage() }
    @objc private func readClipboard() { model.pasteImage(recogniseText: true) }
    @objc private func recordScreen() {
        // A menu key equivalent must retain the Video shortcut's explicit format.
        if let event = NSApp.currentEvent, event.type == .keyDown, let binding = shortcuts.bindings["video"],
           UInt32(event.keyCode) == binding.keyCode,
           event.modifierFlags.intersection([.command, .control, .option, .shift]) == binding.menuModifiers {
            model.record(format: .video)
        } else { model.record() }
    }
    @objc private func recordVideo() { model.record(format: .video) }
    @objc private func recordGIF() { model.record(format: .gif) }
    @objc private func stopRecording() { model.stopRecording() }
    @objc private func pdfMarkdown() { showFiles(.markdown) }
    @objc private func pdfLatex() { showFiles(.latex) }
    @objc private func cancelJob() { model.cancelJob() }
    private func reopen() {
        guard !model.busy, !overlays.hasOpenEditors else {
            model.report(BakerError(message: "Finish the current operation and close capture editors before reopening Baker.", code: .invalidState)); return
        }
        do { try AppReopen.schedule(); NSApp.terminate(nil) }
        catch { model.report(error) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showPreview() {
        if let record = model.captures.first { overlays.show(record) }
    }
    @objc private func openCaptureFolder() { model.revealCaptures() }
    @objc private func showHistory() {
        model.refreshCaptureHistory(enforceLimits: true)
        _ = windows.resolve(.history) {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 840, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Baker · Capture History"
            panel.contentMinSize = NSSize(width: 720, height: 460)
            panel.contentView = NSHostingView(rootView: CaptureHistoryView(model: model, show: { [weak self] in self?.overlays.show($0) }))
            return panel
        }
        windows.show(.history)
    }
    @objc private func newFormulaWorkspace() {
        if model.focusedFormulaID == nil,
           let latest = model.captures.first(where: { model.savedFormulas[$0.id] != nil }) {
            model.openSavedFormula(latest.id)
        }
        model.formulaInputPending = true
        showFormulaWorkspace()
    }
    @objc private func showFormulaWorkspace() {
        let hasResult = model.focusedFormulaID.flatMap { model.formulaResults[$0] } != nil
        let panel = windows.resolve(.formula) {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 740, height: hasResult ? 700 : 400),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Baker · Formula"
            panel.becomesKeyOnlyIfNeeded = true
            panel.minSize = NSSize(width: 680, height: hasResult ? 560 : 400)
            panel.contentView = CaptureHostingView(rootView: FormulaWorkspace(model: model, showHistory: { [weak self] in self?.showHistory() }))
            return panel
        }
        if hasResult {
            panel.minSize = NSSize(width: 680, height: 560)
            if (panel.contentView?.bounds.height ?? 0) < 520 { panel.setContentSize(NSSize(width: max(740, panel.contentView?.bounds.width ?? 0), height: 700)) }
        }
        windows.show(.formula, presentation: .passive)
    }
    @objc private func showResult() {
        _ = windows.resolve(.result) {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Baker · Result"
            panel.contentView = NSHostingView(rootView: ResultView(model: model))
            return panel
        }
        windows.show(.result)
    }
    @objc private func showSettings() { openSettings() }
    private func openSettings(_ page: SettingsPage? = nil) {
        if let page { settingsState.page = page }
        _ = windows.resolve(.settings) {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 620),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 780, height: 560)
            window.title = "Baker · Settings"
            window.contentView = NSHostingView(rootView: BakerSettings(model: model, shortcuts: shortcuts, state: settingsState))
            return window
        }
        windows.show(.settings)
    }

    @objc private func showExport() {
        _ = windows.resolve(.export) {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 460, height: 300),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Baker · Export"
            panel.contentView = NSHostingView(rootView: ExportView(model: model))
            return panel
        }
        windows.show(.export)
    }
}

private struct ExportView: View {
    @ObservedObject var model: Workbench
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.isConvertingPDF ? "Converting PDF" : model.exportURL?.lastPathComponent ?? "Export",
                  systemImage: model.isConvertingPDF ? "doc.text.magnifyingglass" : "doc.badge.checkmark")
                .font(.title3.weight(.semibold)).lineLimit(2)
            Text(model.exportSummary).font(BakerTypography.body).foregroundStyle(.secondary)
            if model.isConvertingPDF { DocumentProgressView(progress: model.documentProgress) }
            Text(model.status).font(BakerTypography.supporting).foregroundStyle(.secondary)
            HStack {
                if model.isConvertingPDF { Button("Cancel", action: model.cancelJob) }
                Spacer()
                Button("Save & Copy…", action: model.copyExport).disabled(model.busy || model.exportURL == nil)
                Button("Save…", action: model.saveExport).buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(model.busy || model.exportURL == nil)
            }
        }.padding(24).frame(minWidth: 420, minHeight: 240).background(BakerTheme.background)
    }
}

private struct ResultView: View {
    @ObservedObject var model: Workbench
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.format.rawValue).font(.headline)
                Spacer()
                if model.format != .text {
                    Button("Apply & Copy", action: model.applyFormulaEdits).disabled(model.busy || model.latex.isEmpty)
                }
                Button("Copy", action: model.copyOutput).disabled(model.output.isEmpty)
            }
            Group {
                switch model.format {
                case .text: TextEditor(text: $model.text)
                case .latex, .keynote, .markdown: TextEditor(text: $model.latex)
                case .unicode: TextEditor(text: $model.unicode)
                }
            }.scrollContentBackground(.hidden).background(BakerTheme.surface).disabled(model.busy).font(model.format == .unicode ? Font(model.selectedMathFont.resolvedFont) : .system(size: 16, design: .monospaced))
            if model.format == .unicode { Text(model.unicodeMessage).font(BakerTypography.supporting).foregroundStyle(.secondary) }
            Text(model.status).font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.padding(16).frame(minWidth: 420, minHeight: 260).background(BakerTheme.background)
    }
}
