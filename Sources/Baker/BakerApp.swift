import AppKit
import BakerCore
import Combine
import SwiftUI

@main
@MainActor
struct BakerApp {
    static func main() {
        let application = NSApplication.shared
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
    private var history: NSPanel?
    private var result: NSPanel?
    private var formulaWorkspace: NSPanel?
    private var settings: NSWindow?
    private var export: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var terminating = false
    private var hiddenUtilityWindows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
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
                self.hiddenUtilityWindows = [self.formulaWorkspace, self.result, self.history, self.export].compactMap { $0 }.filter { $0.isVisible }
                self.hiddenUtilityWindows.forEach { $0.orderOut(nil) }
            }
        }
        model.onExportReady = { [weak self] in self?.showExport() }
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
        menu.addItem(item("Area", #selector(captureRegion), symbol: "viewfinder", enabled: !model.busy))
        menu.addItem(item("Scrolling", #selector(captureScroll), symbol: "scroll", custom: "capture-scroll", enabled: !model.busy))
        menu.addItem(item("Text", #selector(captureText), symbol: "text.viewfinder", custom: "capture-text", enabled: !model.busy))
        menu.addItem(item("Formula", #selector(captureFormula), symbol: "function", custom: "capture-formula", enabled: !model.busy))
        menu.addItem(.separator()); menu.addItem(heading("RECORD"))
        menu.addItem(item("Video…", #selector(recordVideo), symbol: "video", enabled: !model.busy))
        menu.addItem(item("GIF…", #selector(recordGIF), symbol: "photo.stack", enabled: !model.busy))
        if model.isRecording {
            menu.addItem(item("Stop Recording", #selector(stopRecording), symbol: "stop.circle.fill"))
        }
        menu.addItem(.separator()); menu.addItem(heading("CLIPBOARD & FILES"))
        menu.addItem(item("Open Image…", #selector(openImage), symbol: "folder", enabled: !model.busy))
        menu.addItem(item("Open Clipboard Image", #selector(pasteImage), symbol: "clipboard", enabled: !model.busy))
        menu.addItem(item("Read Clipboard Text", #selector(readClipboard), symbol: "text.viewfinder", enabled: !model.busy))
        let pdf = item("Convert PDF", #selector(pdfMarkdown), symbol: "doc.richtext", enabled: !model.busy)
        let pdfFormats = NSMenu(title: "PDF format"); pdfFormats.autoenablesItems = false
        pdfFormats.addItem(item("Markdown…", #selector(pdfMarkdown), symbol: "text.alignleft", enabled: !model.busy))
        pdfFormats.addItem(item("LaTeX…", #selector(pdfLatex), symbol: "function", enabled: !model.busy))
        pdf.submenu = pdfFormats; menu.addItem(pdf)
        if model.busy && !model.isRecording {
            menu.addItem(item("Cancel Processing", #selector(cancelJob), symbol: "xmark.circle"))
        }
        menu.addItem(.separator()); menu.addItem(heading("RECENT"))
        menu.addItem(item("Last Capture…", #selector(showPreview), symbol: "photo", enabled: !model.captures.isEmpty))
        menu.addItem(item("Capture History…", #selector(showHistory), symbol: "photo.stack"))
        menu.addItem(item("Open Capture Folder", #selector(openCaptureFolder), symbol: "folder"))
        menu.addItem(item("Formula Workspace…", #selector(showFormulaWorkspace), symbol: "function"))
        menu.addItem(item("Last Result…", #selector(showResult), symbol: "doc.text"))
        menu.addItem(item("Last Export…", #selector(showExport), symbol: "doc", enabled: model.exportURL != nil || model.isConvertingPDF))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), symbol: "gearshape", key: ","))
        menu.addItem(item("Quit Baker", #selector(quit), symbol: "power", key: "q"))
    }
    @objc private func captureRegion() { model.capture(scrolling: false) }
    @objc private func captureScroll() { model.capture(scrolling: true) }
    @objc private func captureText() { model.capture(scrolling: false, action: .text) }
    @objc private func captureFormula() { model.capture(scrolling: false, action: .formula) }
    @objc private func captureUnicode() { model.capture(scrolling: false, action: .unicode) }
    @objc private func openImage() { NSApp.activate(ignoringOtherApps: true); model.openImage() }
    @objc private func pasteImage() { model.pasteImage() }
    @objc private func readClipboard() { model.pasteImage(recogniseText: true) }
    @objc private func recordVideo() { model.record(format: .video) }
    @objc private func recordGIF() { model.record(format: .gif) }
    @objc private func stopRecording() { model.stopRecording() }
    @objc private func pdfMarkdown() { model.convertPDF(format: .markdown) }
    @objc private func pdfLatex() { model.convertPDF(format: .latex) }
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
    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 620),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Baker · Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: BakerSettings(model: model)); window.center(); settings = window
        }
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

private struct BakerSettings: View {
    @ObservedObject var model: Workbench
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ScrollView { Form {
            HStack(spacing: 12) {
                if let icon = BakerImages.appIcon(dark: colorScheme == .dark) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baker").font(.title2.weight(.semibold))
                    Text("Capture. Recognise. Create.").foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Clipboard workflow").font(.headline)
            Toggle("Play capture sounds", isOn: $model.captureSounds)
            Toggle("Copy captured images automatically", isOn: $model.copyCapturedImages)
            Toggle("Copy recognised text automatically", isOn: $model.copyRecognisedText)
            Text("Formula captures always copy the selected LaTeX, Keynote or Unicode format.").font(.caption).foregroundStyle(.secondary)
            Toggle("Open result editor after recognition", isOn: $model.showResults)
            Divider()
            Picker("Unicode maths font", selection: $model.mathFont) {
                ForEach(MathFont.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            Text("𝑥² + 𝛼𝑥 + ½ = 0").font(Font(model.selectedMathFont.resolvedFont))
            Text(model.selectedMathFont.installedFont == nil
                 ? "This font is not installed. Using \(model.selectedMathFont.resolvedFont.familyName ?? "the system font") instead."
                 : "Copies editable Unicode and formatted text. Paste normally to retain the maths font.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Capture previews").font(.headline)
            Stepper("Visible captures: \(model.visibleCaptures)", value: $model.visibleCaptures, in: 1...5)
            Text("Captures are saved in Pictures/Baker before appearing. Closing a preview keeps its file in history.").font(.caption).foregroundStyle(.secondary)
            Button("Open Capture Folder", action: model.revealCaptures)
            Divider()
            Text("Local formula model").font(.headline)
            TextField("Python executable", text: $model.python)
            TextField("Model configuration JSON", text: $model.config)
            Text("Choose an existing local runtime and model. No sign-in or online OCR service is used.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity) }.frame(width: 600)
    }
}
