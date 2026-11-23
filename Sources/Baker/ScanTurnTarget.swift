import AppKit
import ApplicationServices
import BakerCore

enum ScrollInputEvent {
    static func make(pixels: Int32, point: CGPoint, windowNumber: Int, bounds: CGRect) -> CGEvent? {
        guard pixels > 0, windowNumber > 0, bounds.contains(point) else { return nil }
        let local = CGPoint(x: point.x - bounds.minX, y: bounds.height - (point.y - bounds.minY))
        guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: local, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0)?.cgEvent,
              let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -pixels, wheel2: 0, wheel3: 0) else { return nil }
        // Keep AppKit's window-relative position; setting the global location discards it.
        event.type = .scrollWheel
        let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3,
            .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis3,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3,
            .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase]
        for field in fields { event.setIntegerValueField(field, value: wheel.getIntegerValueField(field)) }
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowNumber))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowNumber))
        return event
    }
}

/// Automatic input is pinned to one selected reader window; never send keys to a different app or window.
@MainActor struct ScanTurnTarget {
    let application: NSRunningApplication
    let element: AXUIElement
    let origin: CGPoint
    let size: CGSize
    let windowNumber: Int?
    let point: CGPoint?
    private let button: AXUIElement?
    private let keyCode: CGKeyCode
    init(application: NSRunningApplication, region: CaptureRegion, point: CGPoint?, expectedWindow: CGRect?, expectedTitle: String?, keyCode: CGKeyCode = 124) throws {
        guard AXIsProcessTrusted() else { throw BakerError(message: "Allow Baker to control the reader in System Settings.", code: .permissionDenied) }
        self.application = application; self.point = point; self.keyCode = keyCode
        element = try Self.focused(application.processIdentifier)
        origin = try Self.point(element); size = try Self.size(element)
        windowNumber = Self.windowNumber(pid: application.processIdentifier, frame: CGRect(origin: origin, size: size))
        if let expectedWindow {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
            guard abs(origin.x - expectedWindow.minX) < 3, abs(origin.y - expectedWindow.minY) < 3,
                  abs(size.width - expectedWindow.width) < 3, abs(size.height - expectedWindow.height) < 3,
                  expectedTitle == nil || expectedTitle == "" || title as? String == expectedTitle else {
                throw BakerError(message: "Focus the selected reader window, then resume auto scan.", code: .invalidState)
            }
        }
        if let point, !CGRect(origin: origin, size: size).contains(point) {
            throw BakerError(message: "Choose a next-page button inside the reader window.", code: .invalidInput)
        }
        let top = NSScreen.screens.first?.frame.maxY ?? region.screen.frame.maxY
        let centre = CGPoint(x: region.screen.frame.minX + region.rect.midX,
            y: top - region.screen.frame.maxY + region.rect.midY)
        guard CGRect(origin: origin, size: size).contains(centre) else { throw BakerError(message: "Focus the reader containing the scan area before auto turn.", code: .invalidState) }
        if let point { button = Self.pressable(at: point, application: application.processIdentifier, window: element) }
        else { button = nil }
        try validate()
    }
    func validate() throws {
        guard !application.isTerminated, AXIsProcessTrusted(),
              CFEqual(try Self.focused(application.processIdentifier), element), try Self.point(element) == origin, try Self.size(element) == size else {
            throw BakerError(message: "Auto turn paused because the selected window moved or changed.", code: .invalidState)
        }
    }
    func advance() throws {
        try validate()
        if let button {
            var window: CFTypeRef?
            guard AXUIElementCopyAttributeValue(button, kAXWindowAttribute as CFString, &window) == .success,
                  let window, CFEqual(window, element) else {
                throw BakerError(message: "The selected next-page button changed. Select it again.", code: .invalidState)
            }
            var enabled: CFTypeRef?
            if AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &enabled) == .success,
               let enabled = enabled as? Bool, !enabled { return }
            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                throw BakerError(message: "The reader did not accept the next-page action.", code: .operationFailed)
            }
            return
        }
        if let point {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { throw BakerError(message: "Could not click the next-page button.", code: .operationFailed) }
            down.flags = []; up.flags = []; down.postToPid(application.processIdentifier); up.postToPid(application.processIdentifier); return
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { throw BakerError(message: "Could not turn the page.", code: .operationFailed) }
        down.flags = []; up.flags = []; down.postToPid(application.processIdentifier); up.postToPid(application.processIdentifier)
    }
    func scroll(pixels: Int32, at point: CGPoint) throws {
        try validate()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
              CGRect(origin: origin, size: size).contains(point) else {
            throw BakerError(message: "Auto Scroll paused. Return to the selected window to continue.", code: .invalidState)
        }
        guard let windowNumber, let event = ScrollInputEvent.make(pixels: pixels, point: point, windowNumber: windowNumber,
            bounds: CGRect(origin: origin, size: size)) else {
            throw BakerError(message: "Could not scroll the selected window.", code: .operationFailed)
        }
        event.postToPid(application.processIdentifier)
    }
    private static func windowNumber(pid: pid_t, frame: CGRect) -> Int? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? Int32 == pid, window[kCGWindowLayer as String] as? Int == 0,
                  let value = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: value as CFDictionary),
                  abs(bounds.minX - frame.minX) < 3, abs(bounds.minY - frame.minY) < 3,
                  abs(bounds.width - frame.width) < 3, abs(bounds.height - frame.height) < 3 else { continue }
            return window[kCGWindowNumber as String] as? Int
        }
        return nil
    }
    private static func pressable(at point: CGPoint, application: pid_t, window: AXUIElement) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(application), Float(point.x), Float(point.y), &hit) == .success else { return nil }
        for _ in 0..<8 {
            guard let current = hit else { break }
            var owner: CFTypeRef?, names: CFArray?
            if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &owner) == .success,
               let owner, CFEqual(owner, window), AXUIElementCopyActionNames(current, &names) == .success,
               let actions = names as? [String], actions.contains(kAXPressAction as String) { return current }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            hit = (parent as! AXUIElement)
        }
        return nil
    }
    static func focusSelected(_ application: NSRunningApplication, frame: CGRect, title: String) async throws {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            throw BakerError(message: "Could not access the selected reader window.", code: .permissionDenied)
        }
        let selected = windows.first { window in
            guard let origin = try? point(window), let size = try? size(window) else { return false }
            var name: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &name)
            return abs(origin.x - frame.minX) < 3 && abs(origin.y - frame.minY) < 3
                && abs(size.width - frame.width) < 3 && abs(size.height - frame.height) < 3
                && (title.isEmpty || name as? String == title)
        }
        guard let selected else { throw BakerError(message: "The selected reader window changed. Select it again.", code: .invalidState) }
        AXUIElementPerformAction(selected, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(selected, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, selected)
        for _ in 0..<20 {
            try Task.checkCancellation()
            if let current = try? focused(application.processIdentifier), CFEqual(current, selected) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw BakerError(message: "Focus the selected reader window, then resume auto scan.", code: .invalidState)
    }
    private static func focused(_ pid: pid_t) throws -> AXUIElement {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { throw BakerError(message: "Focus the reader window before auto turn.", code: .invalidState) }
        return value as! AXUIElement
    }
    private static func point(_ element: AXUIElement) throws -> CGPoint {
        var value: CFTypeRef?; var point = CGPoint.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgPoint, &point) else { throw BakerError(message: "Could not locate the reader window.", code: .invalidState) }
        return point
    }
    private static func size(_ element: AXUIElement) throws -> CGSize {
        var value: CFTypeRef?; var size = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgSize, &size) else { throw BakerError(message: "Could not read the reader window size.", code: .invalidState) }
        return size
    }
}
