import AppKit
import BakerCore

/// Runs before Workbench or permission setup exists; this process never becomes a second Baker session.
@MainActor final class DMGInstaller: NSObject, NSApplicationDelegate {
    private let source = Bundle.main.bundleURL
    private let destination = URL(fileURLWithPath: "/Applications/Baker.app", isDirectory: true)
    private var installing = false
    private var progress: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard !anotherBakerIsRunning() else {
            stop(message: "Quit Baker before installing", detail: "Finish your captures or edits, then quit Baker and open this installer again.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Install Baker?"
        alert.informativeText = "Baker will move to Applications and open there."
        alert.addButton(withTitle: "Install"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
        installing = true
        showProgress()
        Task { [self] in
            do {
                let source = source, destination = destination
                let plan = try await Task.detached(priority: .userInitiated) {
                    try AppInstallation.stage(source: source, destination: destination)
                }.value
                guard !anotherBakerIsRunning() else {
                    try? FileManager.default.removeItem(at: plan.staging)
                    throw BakerError(message: "Baker opened while installing. Quit it and try again.", code: .invalidState)
                }
                let backup = try AppInstallation.commit(plan)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { [weak self] application, error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.installing = false; self.progress?.orderOut(nil); self.progress = nil
                        if error != nil || application == nil {
                            let detail = backup == nil ? "Open Baker from Applications."
                                : "Open Baker from Applications. The previous app has been kept until you confirm this version works."
                            self.stop(message: "Baker is installed", detail: detail)
                        } else {
                            if let backup { try? FileManager.default.trashItem(at: backup, resultingItemURL: nil) }
                            NSApp.terminate(nil)
                        }
                    }
                }
            } catch {
                installing = false; self.progress?.orderOut(nil); self.progress = nil
                let detail = (error as? BakerError)?.userDescription
                    ?? "Baker could not be copied to Applications. You can drag it there in Finder instead."
                stop(message: "Installation stopped", detail: detail)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        installing ? .terminateCancel : .terminateNow
    }

    private func anotherBakerIsRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.baker.app")
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
    }

    private func showProgress() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Baker · Install"; panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Installing Baker…")
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.frame = NSRect(x: 20, y: 64, width: 320, height: 22)
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 30, width: 320, height: 16))
        indicator.style = .bar; indicator.isIndeterminate = true; indicator.startAnimation(nil)
        panel.contentView?.addSubview(label); panel.contentView?.addSubview(indicator)
        panel.center(); panel.makeKeyAndOrderFront(nil); progress = panel
    }

    private func stop(message: String, detail: String) {
        let alert = NSAlert(); alert.messageText = message; alert.informativeText = detail
        alert.addButton(withTitle: "OK"); alert.runModal(); NSApp.terminate(nil)
    }
}
