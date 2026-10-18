import AppKit

/// One retained window per workspace. Closing hides it; reopening preserves its view and position.
@MainActor
final class WorkspaceWindows {
    enum Role: String, CaseIterable { case files, history, formula, result, settings, export }
    enum Presentation { case activate, passive }
    private var windows: [Role: NSWindow] = [:]
    func existing(_ role: Role) -> NSWindow? { windows[role] }
    func resolve(_ role: Role, create: () -> NSWindow) -> NSWindow {
        if let window = windows[role] { return window }
        let window = create()
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.identifier = NSUserInterfaceItemIdentifier("baker." + role.rawValue)
        window.center()
        windows[role] = window
        return window
    }
    func show(_ role: Role, presentation: Presentation = .activate) {
        guard let window = windows[role] else { return }
        switch presentation {
        case .activate: window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        case .passive: window.orderFrontRegardless()
        }
    }
    func hide(_ roles: Role...) { for role in roles { windows[role]?.orderOut(nil) } }
    func closeAll() { for window in windows.values { window.close() }; windows.removeAll() }
}
