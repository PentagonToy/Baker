import AppKit
import SwiftUI

@MainActor func run() {
    _ = NSApplication.shared
    var checks = 0, creations = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
    let windows = WorkspaceWindows(), state = SettingsState()
    for role in WorkspaceWindows.Role.allCases {
        let window = windows.resolve(role) {
            creations += 1
            let value = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            value.contentView = NSView(); return value
        }
        let root = window.contentView
        window.setFrameOrigin(CGPoint(x: 37, y: 53))
        state.page = .menu; state.confirmFormulaClear = true
        window.close()
        let reopened = windows.resolve(role) { fatalError("Closed workspace was recreated") }
        check(reopened === window && reopened.contentView === root, "Window and hosted content survive closing")
        check(reopened.frame.origin == CGPoint(x: 37, y: 53), "Reopening preserves position")
        check(!reopened.isReleasedWhenClosed && !reopened.hidesOnDeactivate && reopened.level == .normal, "Common window policy")
        check(reopened.identifier?.rawValue == "baker." + role.rawValue, "Stable role identifier")
        check(state.page == .menu && state.confirmFormulaClear, "Settings state survives reuse")
    }
    check(creations == WorkspaceWindows.Role.allCases.count, "Exactly one window per role")
    state.page = .advanced
    check(state.page == .advanced, "Explicit settings recovery can change the destination")
    windows.hide(.formula, .result)
    windows.closeAll()
    check(WorkspaceWindows.Role.allCases.allSatisfy { windows.existing($0) == nil }, "Shutdown releases all windows")
    print("Window lifecycle:", checks, "checks passed")
}
Task { @MainActor in run(); exit(0) }
dispatchMain()
