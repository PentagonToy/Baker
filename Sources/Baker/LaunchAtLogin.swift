import BakerCore
import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    let available: Bool
    private let offerKey = PreferenceKeys.hasOfferedLaunchAtLogin.name

    init(defaults: UserDefaults = .standard,
         available: Bool = Bundle.main.bundleURL.pathExtension == "app",
         status: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.defaults = defaults; self.available = available
        self.readStatus = status; self.register = register; self.unregister = unregister
        refresh()
    }
    var enabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }
    var description: String {
        if !available { return "Available when running the installed Baker app." }
        switch status {
        case .enabled: return "Baker starts in the menu bar when you log in."
        case .requiresApproval: return "Waiting for your approval in macOS Login Items."
        case .notRegistered: return "Baker starts only when you open it."
        case .notFound: return "macOS cannot find this app registration. Move Baker to Applications and try again."
        @unknown default: return "Check Baker’s status in macOS Login Items."
        }
    }
    func refresh() { status = readStatus() }
    func setEnabled(_ enabled: Bool) {
        guard available else { return }
        defaults.set(true, forKey: offerKey)
        errorMessage = nil; refresh()
        do {
            if enabled {
                if status != .enabled && status != .requiresApproval { try register() }
            } else if status == .enabled || status == .requiresApproval { try unregister() }
        } catch { errorMessage = "Could not change login startup: " + BakerError.wrapping(error).userDescription }
        refresh()
    }
    /// Returns false if no question was needed. Tests inject the choice without showing UI.
    @discardableResult
    func offerIfNeeded(choose: () -> Bool) -> Bool {
        guard available, !defaults.bool(forKey: offerKey) else { return false }
        refresh()
        if status == .enabled || status == .requiresApproval {
            defaults.set(true, forKey: offerKey); return false
        }
        let accepted = choose()
        defaults.set(true, forKey: offerKey)
        if accepted { setEnabled(true) }
        return true
    }
    func presentFirstLaunchOffer() {
        let asked = offerIfNeeded {
            let alert = NSAlert()
            alert.messageText = "Start Baker when you log in?"
            alert.informativeText = "Keep Baker ready in the menu bar. You can change this later in Settings → General."
            // Return selects the non-enabling choice; registration requires an explicit opt-in.
            alert.addButton(withTitle: "Not Now")
            alert.addButton(withTitle: "Enable Launch at Login")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertSecondButtonReturn
        }
        guard asked else { return }
        if let errorMessage {
            let alert = NSAlert(); alert.messageText = "Launch at Login"; alert.informativeText = errorMessage
            alert.addButton(withTitle: "OK"); alert.runModal()
        } else if needsApproval {
            let alert = NSAlert(); alert.messageText = "Approve Baker in Login Items"
            alert.informativeText = "macOS needs your approval before Baker can start at login."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
        }
    }
}

struct LaunchAtLoginSettings: View {
    @ObservedObject var controller: LaunchAtLogin
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Launch at login")
                Spacer()
                Toggle("Launch at login", isOn: Binding(get: { controller.enabled || controller.needsApproval }, set: controller.setEnabled))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!controller.available)
            }.frame(minHeight: 30).help(controller.description)
            if controller.needsApproval {
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = controller.errorMessage { Text(error).font(BakerTypography.supporting).foregroundStyle(.red).textSelection(.enabled) }
        }
        .onAppear { controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refresh() }
    }
}
