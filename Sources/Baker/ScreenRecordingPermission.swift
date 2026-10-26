import AppKit
import CoreGraphics
import SwiftUI

/// Reads public permission state; never edits or resets the macOS privacy database.
@MainActor
final class ScreenRecordingPermission: ObservableObject {
    @Published private(set) var allowed = false
    private let check: () -> Bool
    private let open: () -> Bool
    private let requestAccess: () -> Bool
    init(check: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         request: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
         open: @escaping () -> Bool = {
             NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                 || NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
         }) {
        self.check = check; self.open = open; self.requestAccess = request; refresh()
    }
    func refresh() { allowed = check() }
    func request() { if !check() { _ = requestAccess() }; refresh() }
    @discardableResult func openSettings() -> Bool { open() }
}

struct ScreenRecordingPermissionView: View {
    @ObservedObject var permission: ScreenRecordingPermission
    let busy: Bool
    let reopen: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(permission.allowed ? "Access allowed" : "Access needed", systemImage: permission.allowed ? "checkmark.circle.fill" : "lock.rectangle")
                    .foregroundStyle(permission.allowed ? BakerTheme.success : Color.primary)
                Spacer()
                Button("System Settings…") { permission.openSettings() }
            }
            if !permission.allowed {
                Text("Allow Baker in Screen & System Audio Recording, then return here.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                HStack {
                    Button("Check Again", action: permission.refresh)
                    Button("Reopen Baker", action: reopen).disabled(busy)
                }
            }
        }.onAppear(perform: permission.refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permission.refresh() }
    }
}
