import AppKit
import ApplicationServices
import SwiftUI

@MainActor enum ControlAccess {
    static var settingsName: String {
        if #available(macOS 27, *) { return "Device Control and Data Access" }
        return "Accessibility"
    }
    static func request() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

@MainActor final class StartupPermissions: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var controlAllowed = AXIsProcessTrusted()
    private var window: NSWindow?
    private var completion: (() -> Void)?
    func presentIfNeeded(screen: ScreenRecordingPermission, completion: @escaping () -> Void) {
        screen.refresh()
        let key = "Baker.HasOfferedCapturePermissions"
        guard !UserDefaults.standard.bool(forKey: key), !screen.allowed || !controlAllowed else { completion(); return }
        UserDefaults.standard.set(true, forKey: key)
        self.completion = completion
        let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        value.title = "Baker · Permissions"; value.isReleasedWhenClosed = false; value.delegate = self
        value.contentView = NSHostingView(rootView: StartupPermissionsView(access: self, screen: screen))
        value.center(); window = value
        NSApp.activate(ignoringOtherApps: true); value.makeKeyAndOrderFront(nil)
    }
    func refresh() { controlAllowed = AXIsProcessTrusted() }
    func finish() { window?.close() }
    func windowWillClose(_ notification: Notification) {
        let next = completion; completion = nil; window = nil; next?()
    }
}

private struct StartupPermissionsView: View {
    @ObservedObject var access: StartupPermissions
    @ObservedObject var screen: ScreenRecordingPermission
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ready to capture").font(BakerTypography.title)
            VStack(spacing: 16) {
                permissionRow("Screen recording", symbol: "viewfinder", allowed: screen.allowed) { screen.request() }
                permissionRow("Control other apps", symbol: "keyboard", allowed: access.controlAllowed) { ControlAccess.request(); access.refresh() }
                    .help(ControlAccess.settingsName + " · Used to turn pages during automatic scans.")
            }
            Divider()
            HStack {
                Text("You can allow access later.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                Spacer()
                Button("Continue", action: access.finish).buttonStyle(BakerButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440).fixedSize(horizontal: false, vertical: true)
            .background(BakerTheme.background).tint(BakerTheme.accent)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in screen.refresh(); access.refresh() }
    }
    private func permissionRow(_ title: String, symbol: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
            Text(title).font(BakerTypography.body)
            Spacer()
            if allowed { Image(systemName: "checkmark.circle.fill").foregroundStyle(BakerTheme.success).accessibilityLabel("Allowed") }
            else { Button("Allow…", action: action).buttonStyle(BakerButtonStyle()) }
        }
    }
}
