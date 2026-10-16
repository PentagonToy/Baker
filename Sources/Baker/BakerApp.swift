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
    private var statusItem: NSStatusItem!
    private lazy var overlays = CaptureOverlayController(model: model)
    private var filesWorkspace: NSWindow?
    private var history: NSPanel?
    private var result: NSPanel?
    private var formulaWorkspace: NSPanel?
    private var settings: NSWindow?
    private var export: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var terminating = false
    private var hiddenUtilityWindows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onFormulaSetupNeeded = { [weak self] in self?.openSettings(.formula) }
        model.onOpenFiles = { [weak self] format in self?.showFiles(format) }
        NSApp.setActivationPolicy(.accessory)
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
            self.showFormulaWorkspace()
        }
        model.onResultReady = { [weak self] in
            if self?.model.showResults == true { self?.showResult() }
        }
        model.onCaptureVisibility = { [weak self] visible in
            guard let self else { return }
            self.overlays.setVisible(visible)
            if visible {
                self.hiddenUtilityWindows.forEach { $0.orderFrontRegardless() }
                self.hiddenUtilityWindows = []
            } else {
                self.hiddenUtilityWindows = [self.filesWorkspace, self.formulaWorkspace, self.result, self.history, self.export].compactMap { $0 }.filter { $0.isVisible }
                self.hiddenUtilityWindows.forEach { $0.orderOut(nil) }
            }
        }
        model.onExportReady = { [weak self] in self?.showExport() }
        if !UserDefaults.standard.bool(forKey: "hasShownRecognitionSetup") {
            UserDefaults.standard.set(true, forKey: "hasShownRecognitionSetup")
            openSettings(.formula)
        }
        model.$problem.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] message in
            self?.model.playCaptureFeedback(success: false)
            let alert = NSAlert(); alert.messageText = "Baker"; alert.informativeText = message
            alert.addButton(withTitle: "OK"); NSApp.activate(ignoringOtherApps: true); alert.runModal()
            self?.model.problem = nil
        }.store(in: &subscriptions)
        rebuildMenu(menu)
        model.warmCaptureSelection()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFormulaWorkspace()
        formulaWorkspace?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
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
    func applicationWillTerminate(_ notification: Notification) { model.cleanup() }
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    private func item(_ title: String, _ action: Selector, symbol: String, custom: String? = nil, enabled: Bool = true, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.isEnabled = enabled
        item.image = custom.map { BakerImages.template($0, fallback: symbol) } ?? BakerImages.system(symbol)
        return item
    }
    private func heading(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        return item
    }
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems(); menu.autoenablesItems = false
        menu.addItem(heading("CAPTURE"))
        menu.addItem(item("Area", #selector(captureRegion), symbol: "viewfinder", custom: "capture-area", enabled: !model.busy))
        menu.addItem(item("Scrolling", #selector(captureScroll), symbol: "scroll", custom: "capture-scroll", enabled: !model.busy))
        menu.addItem(item("Text", #selector(captureText), symbol: "text.viewfinder", custom: "capture-text", enabled: !model.busy))
        menu.addItem(item("Formula", #selector(captureFormula), symbol: "function", custom: "capture-formula", enabled: !model.busy))
        menu.addItem(.separator()); menu.addItem(heading("RECORD"))
        menu.addItem(item("Video…", #selector(recordVideo), symbol: "video", custom: "record-video", enabled: !model.busy))
        menu.addItem(item("GIF…", #selector(recordGIF), symbol: "photo.stack", custom: "record-gif", enabled: !model.busy))
        if model.isRecording {
            menu.addItem(item("Stop Recording", #selector(stopRecording), symbol: "stop.circle.fill"))
        }
        menu.addItem(.separator()); menu.addItem(heading("CLIPBOARD & FILES"))
        menu.addItem(item("Open Files…", #selector(openImage), symbol: "folder", custom: "files-open", enabled: !model.busy))
        menu.addItem(item("Open Clipboard Image", #selector(pasteImage), symbol: "clipboard", custom: "clipboard-image", enabled: !model.busy))
        menu.addItem(item("Read Clipboard Text", #selector(readClipboard), symbol: "text.viewfinder", custom: "clipboard-text", enabled: !model.busy))
        let pdf = item("Convert PDF", #selector(pdfMarkdown), symbol: "doc.richtext", custom: "convert-pdf", enabled: !model.busy)
        let pdfFormats = NSMenu(title: "PDF format"); pdfFormats.autoenablesItems = false
        pdfFormats.addItem(item("Markdown…", #selector(pdfMarkdown), symbol: "text.alignleft", enabled: !model.busy))
        pdfFormats.addItem(item("LaTeX…", #selector(pdfLatex), symbol: "function", enabled: !model.busy))
        pdf.submenu = pdfFormats; menu.addItem(pdf)
        if model.busy && !model.isRecording {
            menu.addItem(item("Cancel Processing", #selector(cancelJob), symbol: "xmark.circle"))
        }
        menu.addItem(.separator()); menu.addItem(heading("RECENT"))
        menu.addItem(item("Last Capture…", #selector(showPreview), symbol: "photo", enabled: !model.captures.isEmpty))
        menu.addItem(item("Capture History…", #selector(showHistory), symbol: "photo.stack", custom: "capture-history"))
        menu.addItem(item("Open Capture Folder", #selector(openCaptureFolder), symbol: "folder", custom: "files-open"))
        menu.addItem(item("Formula Workspace…", #selector(showFormulaWorkspace), symbol: "function"))
        menu.addItem(item("Last Result…", #selector(showResult), symbol: "doc.text"))
        menu.addItem(item("Last Export…", #selector(showExport), symbol: "doc", enabled: model.exportURL != nil || model.isConvertingPDF))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), symbol: "gearshape", custom: "settings", key: ","))
        menu.addItem(item("Quit Baker", #selector(quit), symbol: "power", key: "q"))
    }
    @objc private func captureRegion() { model.capture(scrolling: false) }
    @objc private func captureScroll() { model.capture(scrolling: true) }
    @objc private func captureText() { model.capture(scrolling: false, action: .text) }
    @objc private func captureFormula() { model.capture(scrolling: false, action: .formula) }
    @objc private func captureUnicode() { model.capture(scrolling: false, action: .unicode) }
    private func showFiles(_ format: PDFExportFormat? = nil) {
        if let format { model.filesInbox.pdfFormat = format }
        if filesWorkspace == nil {
            let panel = FilesWorkspaceWindow()
            panel.title = "Baker · Clipboard & Files"; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: FilesWorkspace(model: model, inbox: model.filesInbox))
            panel.center(); model.filesInbox.presentationWindow = panel; filesWorkspace = panel
        }
        filesWorkspace?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openImage() { showFiles() }
    @objc private func pasteImage() { model.pasteImage() }
    @objc private func readClipboard() { model.pasteImage(recogniseText: true) }
    @objc private func recordVideo() { model.record(format: .video) }
    @objc private func recordGIF() { model.record(format: .gif) }
    @objc private func stopRecording() { model.stopRecording() }
    @objc private func pdfMarkdown() { showFiles(.markdown) }
    @objc private func pdfLatex() { showFiles(.latex) }
    @objc private func cancelJob() { model.cancelJob() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showPreview() {
        if let record = model.captures.first { overlays.show(record) }
    }
    @objc private func openCaptureFolder() { model.revealCaptures() }
    @objc private func showHistory() {
        if history == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Baker · Capture History"; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: CaptureHistoryView(model: model, show: { [weak self] in self?.overlays.show($0) }))
            panel.center(); history = panel
        }
        history?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showFormulaWorkspace() {
        if model.focusedFormulaID == nil {
            model.focusedFormulaID = model.captures.first { model.formulaResults[$0.id] != nil }?.id
        }
        if formulaWorkspace == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 740, height: 700),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Baker · Formula"; panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true; panel.hidesOnDeactivate = false
            panel.level = .floating; panel.minSize = NSSize(width: 680, height: 560)
            panel.contentView = CaptureHostingView(rootView: FormulaWorkspace(model: model, showHistory: { [weak self] in self?.showHistory() }))
            panel.center(); formulaWorkspace = panel
        }
        formulaWorkspace?.orderFrontRegardless()
    }
    @objc private func showResult() {
        if result == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Baker · Result"; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: ResultView(model: model))
            panel.center(); result = panel
        }
        result?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings() { openSettings(.general) }
    private func openSettings(_ page: SettingsPage) {
        if settings == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 620),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 780, height: 560)
            window.title = "Baker · Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: BakerSettings(model: model)); window.center(); settings = window
        }
        settings?.contentView = NSHostingView(rootView: BakerSettings(model: model, page: page))
        settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showExport() {
        if export == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 460, height: 300),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Baker · Export"; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: ExportView(model: model))
            panel.center(); export = panel
        }
        export?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ExportView: View {
    @ObservedObject var model: Workbench
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.isConvertingPDF ? "Converting PDF" : model.exportURL?.lastPathComponent ?? "Export",
                  systemImage: model.isConvertingPDF ? "doc.text.magnifyingglass" : "doc.badge.checkmark")
                .font(.title3.weight(.semibold)).lineLimit(2)
            Text(model.exportSummary).font(.callout).foregroundStyle(.secondary)
            if model.isConvertingPDF { ProgressView().controlSize(.small) }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.isConvertingPDF { Button("Cancel", action: model.cancelJob) }
                Spacer()
                Button("Save & Copy…", action: model.copyExport).disabled(model.busy || model.exportURL == nil)
                Button("Save…", action: model.saveExport).buttonStyle(.borderedProminent).tint(.orange)
                    .disabled(model.busy || model.exportURL == nil)
            }
        }.padding(24).frame(minWidth: 420, minHeight: 240)
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
            }.disabled(model.busy).font(model.format == .unicode ? Font(model.selectedMathFont.resolvedFont) : .system(size: 16, design: .monospaced))
            if model.format == .unicode { Text(model.unicodeMessage).font(.caption).foregroundStyle(.secondary) }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(minWidth: 420, minHeight: 260)
    }
}
