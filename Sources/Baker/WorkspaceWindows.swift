import AppKit

/// One retained window per workspace. Closing hides it; reopening preserves its view and position.
@MainActor
final class WorkspaceWindows {
    enum Role: String, CaseIterable { case files, history, formula, result, settings, export, guide }
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
        fit(role)
        switch presentation {
        case .activate: window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        case .passive: window.orderFrontRegardless()
        }
    }
    func fit(_ role: Role, on screen: NSScreen? = nil) {
        guard let window = windows[role], let screen = screen ?? window.screen ?? NSScreen.main else { return }
        let frame = Self.constrainedFrame(window.frame, inside: screen.visibleFrame)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }
    static func constrainedFrame(_ frame: CGRect, inside screen: CGRect) -> CGRect {
        let width = min(frame.width, screen.width), height = min(frame.height, screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
    func hide(_ roles: Role...) { for role in roles { windows[role]?.orderOut(nil) } }
    /// Transient popover content is rebuilt on every show; retaining it while closed has no reuse benefit.
    static func releaseClosedPopoverContent(_ popover: NSPopover) {
        guard !popover.isShown else { return }
        popover.contentViewController = nil
    }
    func closeAll() { for window in windows.values { window.close() }; windows.removeAll() }
}
