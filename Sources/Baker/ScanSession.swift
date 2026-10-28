import AppKit
import SwiftUI
import BakerCore
import ApplicationServices
import UniformTypeIdentifiers

/// A scan has no polling stream. Manual capture is idle between explicit page additions.
@MainActor final class ScanSession: NSObject, ObservableObject, NSWindowDelegate {
    enum Phase: String { case setup, selecting, capturing, review, exporting, closed }
    @Published private(set) var phase: Phase = .setup
    @Published private(set) var pages: [ScanPage] = []
    @Published private(set) var draftBytes: Int64 = 0
    @Published var selected: UUID?
    @Published private(set) var working = false
    @Published var message = "Select the page area once."
    @Published var searchable = false
    @Published private(set) var automatic = false
    @Published private(set) var automaticSession = false
    @Published var turnDelay = 3.0
    private var delayNanoseconds: UInt64 { UInt64((turnDelay.isFinite ? min(60, max(0.1, turnDelay)) : 3) * 1_000_000_000) }
    @Published var sourceChoice: ScanSourceChoice = .window
    @Published var advanceChoice: ScanAdvanceChoice = .arrow
    @Published private(set) var accessibilityAllowed = AXIsProcessTrusted()
    private let imagePicker = ScanImagePicker()
    @Published private(set) var sourceName: String?
    @Published private(set) var sourcePreview: NSImage?
    private var windowCrop: CGRect?
    private var clickPoint: CGPoint?
    private var expectedWindow: CGRect?
    private var expectedTitle: String?
    private var startAutomatically = false
    @Published private(set) var exportedURL: URL?
    let draft: ScanDocument
    private let service = CaptureService()
    private let languages: [String]
    private let saveDirectory: URL
    private var region: CaptureRegion?
    private var prepared: PreparedCapture?
    private var windowSource: PreparedCapture?
    private var targetApp: NSRunningApplication?
    private var turnTarget: ScanTurnTarget?
    private var panel: NSPanel?
    private var window: NSWindow?
    @Published private var task: Task<Void, Never>?
    private var autoTask: Task<Void, Never>?
    private var replacement: UUID?
    private var ended: (() -> Void)?
    private var saved: ((URL) -> Void)?
    var pageCountLabel: String { pages.count == 1 ? "1 page" : "\(pages.count) pages" }
    var canAdd: Bool { phase == .capturing && !working && task == nil && prepared != nil && (pages.count < ScanDocument.pageLimit || replacement != nil) }
    var canConfigure: Bool { !working && task == nil && !automatic && [.setup, .review, .capturing].contains(phase) }
    var resourceState: [String: Any] { ["state": phase.rawValue, "pages": pages.count, "working": working,
        "automatic": automatic, "draftBytes": draftBytes, "captureReady": canAdd, "pendingWork": task != nil, "sourcePreviewRetained": sourcePreview != nil] }
    func diagnostic(limit: Int = 20, offset: Int = 0) -> [String: Any] {
        let start = max(0, offset), count = min(100, max(1, limit))
        return resourceState.merging(["draft": draft.directory.path, "message": message, "selected": selected?.uuidString ?? "",
            "source": sourceName ?? "", "capture": sourceChoice == .area ? "area" : "window",
            "advance": advanceChoice == .click ? "click" : advanceChoice == .down ? "down" : "arrow", "delay": turnDelay, "searchable": searchable,
            "offset": start, "limit": count, "hasMore": start < pages.count && count < pages.count - start,
            "items": pages.enumerated().dropFirst(start).prefix(count).map { index, page in
                ["id": page.id.uuidString, "page": index + 1, "width": page.width, "height": page.height,
                 "file": draft.directory.appendingPathComponent(page.fileName).path] as [String: Any]
            }]) { _, value in value }
    }
    func configure(_ options: ScanOptions) throws {
        guard canConfigure else { throw BakerError(message: "Pause the scan and finish the current page before changing options.", code: .invalidState) }
        try options.validate()
        if let delay = options.delay { turnDelay = delay }
        if let searchable = options.searchable { self.searchable = searchable }
    }
    static var draftDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Baker/ScanDraft", isDirectory: true)
    }
    init(draft: ScanDocument, saveDirectory: URL, languages: [String], ended: @escaping () -> Void, saved: @escaping (URL) -> Void) {
        self.draft = draft; self.saveDirectory = saveDirectory; self.languages = languages; self.ended = ended; self.saved = saved
        super.init()
        targetApp = NSWorkspace.shared.frontmostApplication
    }
    func start(resume: Bool) {
        task = Task { [weak self] in
            guard let self else { return }
            pages = await draft.pages(); draftBytes = await draft.storageBytes(); selected = pages.first?.id; task = nil
            guard !Task.isCancelled, phase != .closed else { return }
            if resume && !pages.isEmpty { showReview() } else { showSetup() }
        }
    }
    func refreshAccessibility() { accessibilityAllowed = AXIsProcessTrusted() }
    func openAccessibilitySettings() {
        ControlAccess.request()
        refreshAccessibility()
    }
    private func showSetup() {
        phase = .setup
        if window == nil {
            let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            value.title = "Baker · Scan"; value.isReleasedWhenClosed = false; value.delegate = self; value.center(); window = value
        }
        window?.contentView = NSHostingView(rootView: ScanSetup(session: self))
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func chooseSource() {
        guard !working else { return }
        stopAuto(); phase = .selecting; window?.orderOut(nil); panel?.orderOut(nil)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if let source = try await service.prepareWindow() {
                    try Task.checkCancellation()
                    region = source.region; prepared = source.capture; windowSource = source.capture
                    targetApp = source.application; expectedWindow = source.frame; expectedTitle = source.title
                    sourceName = source.title.isEmpty ? source.application?.localizedName ?? "Selected window" : source.title
                    windowCrop = nil; clickPoint = nil; sourcePreview = nil
                    if let preview = try? await source.capture.preview(), !Task.isCancelled {
                        sourcePreview = NSImage(cgImage: preview, size: .zero)
                    }
                }
                task = nil
                guard !Task.isCancelled, phase != .closed else { return }
                showSetup()
            } catch {
                task = nil
                guard !Task.isCancelled, phase != .closed else { return }
                message = error.localizedDescription
                if phase != .closed { showSetup() }
            }
        }
    }
    func beginConfiguredScan(automatic: Bool) {
        guard !working, phase == .setup, let source = windowSource, let region else { return }
        refreshAccessibility()
        if automatic && !accessibilityAllowed { openAccessibilitySettings(); return }
        turnDelay = turnDelay.isFinite ? min(60, max(0.1, turnDelay)) : 3
        startAutomatically = automatic; clickPoint = nil; window?.orderOut(nil); phase = .selecting
        task = Task { [weak self] in
            guard let self else { return }
            do {
                prepared = source
                if sourceChoice == .area {
                    let image = try await source.image(); try Task.checkCancellation()
                    let selection = await imagePicker.choose(image: image, screen: region.screen, mode: .area)
                    try Task.checkCancellation()
                    guard let crop = selection else {
                        task = nil; startAutomatically = false; showSetup(); return
                    }
                    windowCrop = crop
                } else { windowCrop = nil }
                guard try await prepareClickIfNeeded() else { task = nil; return }
                if automatic, let app = targetApp, let frame = expectedWindow {
                    try await ScanTurnTarget.focusSelected(app, frame: frame, title: expectedTitle ?? "")
                }
                try Task.checkCancellation()
                phase = .capturing; sourcePreview = nil; window?.contentView = nil; showControls(region); task = nil; addPage()
            } catch {
                task = nil; startAutomatically = false
                guard !Task.isCancelled, phase != .closed else { return }
                message = error.localizedDescription
                if phase != .closed { showReview() }
            }
        }
    }
    private func prepareClickIfNeeded() async throws -> Bool {
        guard startAutomatically, advanceChoice == .click, let region, let source = windowSource, let frame = expectedWindow else { return true }
        let image = try await source.image(); try Task.checkCancellation()
        let selection = await imagePicker.choose(image: image, screen: region.screen, mode: .point)
        try Task.checkCancellation()
        guard let result = selection else {
            startAutomatically = false; showSetup(); return false
        }
        try Task.checkCancellation()
        clickPoint = CGPoint(x: frame.minX + result.minX * frame.width, y: frame.minY + result.minY * frame.height)
        return true
    }
    func chooseArea(retake: UUID? = nil) {
        guard !working, phase != .closed else { return }
        replacement = retake; sourceChoice = .area; chooseSource()
    }
    private func capturePage(_ source: PreparedCapture) async throws -> CGImage {
        let image = try await source.image(); try Task.checkCancellation()
        guard let crop = windowCrop else { return image }
        let rect = CGRect(x: crop.minX * CGFloat(image.width), y: crop.minY * CGFloat(image.height),
            width: crop.width * CGFloat(image.width), height: crop.height * CGFloat(image.height)).integral
        guard let cropped = image.cropping(to: rect) else { throw BakerError(message: "Select the page area again.", code: .captureFailed) }
        return cropped
    }
    func continueCapture(retake: UUID? = nil) {
        guard !working else { return }
        stopAuto(); automaticSession = false; replacement = retake
        guard let region else { chooseArea(retake: retake); return }
        window?.orderOut(nil); phase = .capturing; showControls(region)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if let windowSource { prepared = windowSource } else { prepared = try await service.prepare(region) }
                try Task.checkCancellation(); task = nil; if retake != nil { addPage() }
            }
            catch { task = nil; if !Task.isCancelled, phase != .closed { message = error.localizedDescription; showReview() } }
        }
    }
    func addPage() {
        guard canAdd, task == nil, let prepared else { return }
        working = true; message = replacement == nil ? "Adding page…" : "Retaking page…"
        let replacing = replacement
        task = Task { [weak self] in
            guard let self else { return }
            var didAdd = false
            defer {
                working = false; task = nil
                if startAutomatically {
                    startAutomatically = false
                    if didAdd && phase == .capturing { toggleAuto() }
                }
            }
            do {
                let image = try await capturePage(prepared); try Task.checkCancellation()
                var captured = try await draft.append(image, replacing: replacing, rejectDuplicate: automatic)
                if captured == nil && automatic {
                    message = "Checking whether the page has finished…"
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    try Task.checkCancellation(); try turnTarget?.validate()
                    let retry = try await capturePage(prepared); try Task.checkCancellation()
                    captured = try await draft.append(retry, replacing: replacing, rejectDuplicate: true)
                }
                if let page = captured {
                    didAdd = true
                    let previous = pages.last?.fingerprint
                    pages = await draft.pages(); draftBytes = await draft.storageBytes(); selected = page.id; replacement = nil
                    if replacing != nil { message = "Page retaken."; showReview() }
                    else { message = previous == page.fingerprint ? "Page added. It looks like the previous page." : "Turn the page, then add the next one." }
                } else { stopAuto(); message = "No further page change. Review your scan."; showReview(activate: false) }
                if pages.count >= ScanDocument.pageLimit { stopAuto(); message = "500 pages reached. Review and save this scan."; showReview(activate: false) }
            } catch {
                stopAuto()
                if !(error is CancellationError) { message = error.localizedDescription }
            }
        }
    }
    func toggleAuto() {
        if automatic { pauseAuto(); return }
        do { try resumeAuto() } catch { message = error.localizedDescription }
    }
    func pauseAuto() { guard automatic else { return }; stopAuto(); message = "Auto turn paused." }
    func resumeAuto() throws {
        guard !automatic, canAdd, replacement == nil, let app = targetApp, let region,
              advanceChoice != .click || clickPoint != nil else {
            throw BakerError(message: "Prepare the reader and next-page action before resuming auto scan.", code: .invalidState)
        }
        turnTarget = try ScanTurnTarget(application: app, region: region, point: clickPoint, expectedWindow: expectedWindow, expectedTitle: expectedTitle, keyCode: advanceChoice == .down ? 125 : 124)
        automatic = true; automaticSession = true; message = clickPoint == nil ? "Scanning with \(advanceChoice == .down ? "↓" : "→")." : "Scanning with the selected button."
        autoTask = Task { [weak self] in
            guard let self else { return }
            // Explicit timing, not a guess that a reader has finished loading.
            let started = ProcessInfo.processInfo.systemUptime
            while automatic && !Task.isCancelled && phase == .capturing {
                do {
                    guard ProcessInfo.processInfo.systemUptime - started < 1200 else { throw BakerError(message: "Auto turn paused after 20 minutes. Review your pages.", code: .resourceLimit) }
                    try turnTarget?.advance()
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    try Task.checkCancellation(); try turnTarget?.validate()
                    addPage(); let captureTask = task; await captureTask?.value
                } catch {
                    if !(error is CancellationError) { message = error.localizedDescription }
                    stopAuto(); break
                }
            }
        }
    }
    func stopAuto() { automatic = false; autoTask?.cancel(); autoTask = nil; turnTarget = nil }
    func present() {
        if phase == .setup || phase == .review || phase == .exporting { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
        else { review() }
    }
    func review() {
        guard phase == .capturing || phase == .selecting else { return }
        startAutomatically = false; stopAuto(); service.cancelSelection(); imagePicker.cancel()
        if working { message = "Finishing the current page…"; let pending = task; Task { [weak self] in await pending?.value; self?.showReview() } }
        else { task?.cancel(); task = nil; showReview() }
    }
    private func showReview(activate: Bool = true) {
        guard phase != .closed else { return }
        if message == "Select the page area once." || message == "Turn the page, then add the next one." {
            message = "Review pages, then save. Closing keeps your draft."
        }
        stopAuto(); prepared = nil; sourcePreview = nil; phase = .review; panel?.contentView = nil; panel?.close(); panel = nil
        if window == nil {
            let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            value.title = "Baker · Scan"; value.minSize = NSSize(width: 620, height: 500); value.isReleasedWhenClosed = false
            value.delegate = self; value.center(); window = value
        }
        window?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window?.minSize = NSSize(width: 620, height: 500)
        if let window, window.frame.width < 620 || window.frame.height < 500 { window.setContentSize(NSSize(width: 780, height: 660)); window.center() }
        window?.contentView = NSHostingView(rootView: ScanReview(session: self))
        if activate { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
        else { window?.orderFront(nil) }
    }
    private func showControls(_ region: CaptureRegion) {
        let visible = region.screen.visibleFrame
        let p = NSPanel(contentRect: NSRect(x: visible.minX + 18, y: visible.minY + 18, width: 448, height: 126),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Baker · Scan Controls"; p.level = .floating; p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.contentView = NSHostingView(rootView: ScanControls(session: self)); panel?.contentView = nil; panel?.close(); panel = p; p.orderFrontRegardless()
    }
    func discard() {
        guard !working else { return }
        working = true; stopAuto()
        task = Task { [weak self] in
            guard let self else { return }
            do { try await draft.discard(); draftBytes = 0; working = false; task = nil; keepAndClose() }
            catch { message = error.localizedDescription; working = false; task = nil }
        }
    }
    func removeSelected() {
        guard !working, let selected else { return }
        edit { try await self.draft.remove(selected) }
    }
    func moveSelected(_ offset: Int) {
        guard !working, let selected else { return }
        edit { try await self.draft.move(selected, by: offset) }
    }
    private func edit(_ action: @escaping () async throws -> Void) {
        working = true
        task = Task { [weak self] in
            guard let self else { return }; defer { working = false; task = nil }
            do { try await action(); pages = await draft.pages(); draftBytes = await draft.storageBytes(); if !pages.contains(where: { $0.id == self.selected }) { selected = pages.first?.id } }
            catch { message = error.localizedDescription }
        }
    }
    func savePDF(to destination: URL? = nil) {
        guard phase == .review, !working, !pages.isEmpty else { return }
        var target = destination; var replace = false
        if target == nil {
            let picker = NSSavePanel(); picker.allowedContentTypes = [.pdf]; picker.directoryURL = saveDirectory
            let date = DateFormatter(); date.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            picker.nameFieldStringValue = "baker_scan_" + date.string(from: Date()) + ".pdf"
            guard picker.runModal() == .OK else { return }; target = picker.url; replace = true
        }
        guard let target else { return }
        stopAuto(); phase = .exporting; working = true; message = "Saving PDF…"
        let searchable = searchable, languages = languages
        task = Task { [weak self] in
            guard let self else { return }
            defer { working = false; task = nil; if phase != .closed { phase = .review } }
            do {
                try await draft.export(to: target, searchable: searchable, languages: languages, replace: replace) { [weak self] count, total in
                    Task { @MainActor [weak self] in if self?.phase == .exporting { self?.message = "Saving page \(count) of \(total)…" } }
                }
                exportedURL = target; message = "PDF saved."; saved?(target)
                // A successful PDF is the only final output. Remove its working page files.
                do { try await draft.discard(); draftBytes = 0; pages = []; working = false; keepAndClose() }
                catch { message = "PDF saved. The working draft could not be removed; you can close it safely." }
            } catch { message = error is CancellationError ? "Saving cancelled. Your pages are kept." : error.localizedDescription }
        }
    }
    func cancelExport() { if phase == .exporting { task?.cancel() } }
    func keepAndClose() {
        guard !working else { return }
        phase = .closed; startAutomatically = false; stopAuto(); service.cancelSelection(); imagePicker.cancel(); panel?.contentView = nil; panel?.close(); panel = nil
        window?.delegate = nil; window?.contentView = nil; window?.close(); window = nil; prepared = nil; windowSource = nil; sourcePreview = nil; region = nil
        let callback = ended; ended = nil; saved = nil; callback?()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { await close() }
        return false // Cancel pending work before closing, keeping the recoverable draft.
    }
    func close() async {
        guard phase != .closed else { return }
        phase = .closed; working = true; message = "Stopping scan…"
        startAutomatically = false; stopAuto(); task?.cancel(); service.cancelSelection(); imagePicker.cancel(); let pending = task; await pending?.value
        working = false; task = nil; keepAndClose()
    }
}
