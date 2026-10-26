import AppKit
import Carbon
import SwiftUI

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for (carbon, flag) in [(cmdKey, NSEvent.ModifierFlags.command), (controlKey, .control), (optionKey, .option), (shiftKey, .shift)] {
            if modifiers & UInt32(carbon) != 0 { flags.insert(flag) }
        }
        return flags
    }

    var menuKey: String {
        guard keyCode <= UInt16.max else { return "" }
        let special: [UInt32: String] = [48:"\t",49:" ",36:"\r",76:"\u{3}",53:"\u{1b}",51:"\u{8}",
            117:String(UnicodeScalar(NSDeleteFunctionKey)!),123:String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            124:String(UnicodeScalar(NSRightArrowFunctionKey)!),125:String(UnicodeScalar(NSDownArrowFunctionKey)!),
            126:String(UnicodeScalar(NSUpArrowFunctionKey)!),115:String(UnicodeScalar(NSHomeFunctionKey)!),
            119:String(UnicodeScalar(NSEndFunctionKey)!),116:String(UnicodeScalar(NSPageUpFunctionKey)!),
            121:String(UnicodeScalar(NSPageDownFunctionKey)!)]
        if let value = special[keyCode] { return value }
        let functions: [UInt32: Int] = [122:0,120:1,99:2,118:3,96:4,97:5,98:6,100:7,101:8,109:9,103:10,111:11]
        if let offset = functions[keyCode] { return String(UnicodeScalar(NSF1FunctionKey + offset)!) }
        // Global bindings use physical key codes; display the current layout's unshifted key.
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var dead: UInt32 = 0, length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, characters.count, &length, &characters)
            if status == noErr, length > 0 { return String(utf16CodeUnits: characters, count: length).lowercased() }
        }
        return String(label.drop(while: { "⌃⌥⇧⌘".contains($0) })).lowercased()
    }
}

/// System hot keys work while another app is active, without an accessibility event tap.
@MainActor
final class CaptureShortcuts: ObservableObject {
    static let actions = [("area", "Area", "capture-area"), ("scroll", "Scrolling", "capture-scroll"),
                          ("text", "Text", "capture-text"), ("formula", "Formula", "capture-formula"),
                          ("video", "Video", "record-video"), ("gif", "GIF", "record-gif"),
                          ("all", "All", "capture-all"), ("repeat", "Repeat Area", "capture-repeat"), ("window", "Window", "macwindow")]
    @Published private(set) var bindings: [String: CaptureShortcut] = [:]
    @Published var message: String?
    private var registrations: [String: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private(set) var recording = false
    private var symbolicMode: UnsafeMutableRawPointer?
    func beginRecording() {
        guard !recording else { return }
        recording = true; message = nil
        symbolicMode = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabledExceptUniversalAccess))
        for ref in registrations.values { UnregisterEventHotKey(ref) }
        registrations.removeAll()
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        if let symbolicMode { PopSymbolicHotKeyMode(symbolicMode) }; symbolicMode = nil
        for (action, binding) in bindings where registrations[action] == nil { register(action, binding) }
    }
    var perform: ((String) -> Void)?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: PreferenceKeys.captureShortcuts.name),
           let saved = try? JSONDecoder().decode([String: CaptureShortcut].self, from: data) { bindings = saved }
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x42414B52 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<CaptureShortcuts>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                let index = Int(id.id) - 1
                if !owner.recording && CaptureShortcuts.actions.indices.contains(index) { owner.perform?(CaptureShortcuts.actions[index].0) }
            }
            return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))],
           Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (action, binding) in bindings { register(action, binding) }
    }
    @discardableResult func set(_ action: String, _ binding: CaptureShortcut?) -> Bool {
        if let binding, bindings.contains(where: { $0.key != action && $0.value.keyCode == binding.keyCode && $0.value.modifiers == binding.modifiers }) {
            message = "That shortcut is already assigned to another Baker action."; return false
        }
        let previous = bindings[action]
        if let ref = registrations.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        message = nil
        if let binding, !register(action, binding) {
            if let previous { register(action, previous) }; return false
        }
        bindings[action] = binding
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: PreferenceKeys.captureShortcuts.name) }
        return true
    }
    @discardableResult private func register(_ action: String, _ binding: CaptureShortcut) -> Bool {
        guard let index = Self.actions.firstIndex(where: { $0.0 == action }) else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
            EventHotKeyID(signature: 0x42414B52, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { message = "The shortcut for \(Self.actions[index].1) is unavailable. Choose another combination."; return false }
        registrations[action] = ref; return true
    }
    deinit {
        if let symbolicMode { PopSymbolicHotKeyMode(symbolicMode) }
        for ref in registrations.values { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let binding: CaptureShortcut?
    let changed: (CaptureShortcut?) -> Bool
    let recordingChanged: (Bool) -> Void
    func makeNSView(context: Context) -> ShortcutButton { ShortcutButton() }
    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.idleTitle = binding?.label ?? "Record Shortcut"
        if !button.recording { button.title = button.idleTitle }
        button.changed = changed; button.recordingChanged = recordingChanged
    }
}
final class ShortcutButton: NSButton {
    var changed: ((CaptureShortcut?) -> Bool)?
    var recordingChanged: ((Bool) -> Void)?
    var idleTitle = "Record Shortcut"
    private(set) var recording = false
    private var monitor: Any?
    private var resignation: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); bezelStyle = .rounded; target = self; action = #selector(record)
        toolTip = "Click, then press a shortcut. Escape cancels; Delete clears."
        setAccessibilityLabel("Record shortcut")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func record() {
        if recording { finishRecording(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        recording = true; title = "Press shortcut…"; bezelColor = .controlAccentColor; recordingChanged?(true)
        resignation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishRecording() }
        }
        // Intercept before AppKit turns Tab into focus navigation or a key equivalent.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, event.window === self.window else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command, ["q", "w", ","].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") {
                self.finishRecording(); return event
            }
            self.keyDown(with: event); return nil
        }
    }
    func finishRecording() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resignation { NotificationCenter.default.removeObserver(resignation) }; resignation = nil
        recording = false; title = idleTitle; bezelColor = nil; recordingChanged?(false)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53 && flags.isEmpty { finishRecording(); window?.makeFirstResponder(nil); return }
        if (event.keyCode == 51 || event.keyCode == 117) && flags.isEmpty {
            if changed?(nil) == true { finishRecording(); window?.makeFirstResponder(nil) }; return
        }
        guard flags.contains(.command) || flags.contains(.control) else { title = "Include ⌘ or ⌃"; return }
        var modifiers: UInt32 = 0, prefix = ""
        for (flag, carbon, glyph) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(carbon); prefix += glyph }
        }
        let special: [UInt16: String] = [48:"⇥",49:"Space",36:"↩",76:"⌤",53:"⎋",51:"⌫",117:"⌦",123:"←",124:"→",125:"↓",126:"↑",115:"↖",119:"↘",116:"⇞",121:"⇟"]
        let function: [UInt16: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
        guard let key = special[event.keyCode] ?? function[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return }
        if changed?(CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: prefix + key)) == true {
            finishRecording(); window?.makeFirstResponder(nil)
        } else { title = "Try another shortcut…" }
    }
    override func resignFirstResponder() -> Bool { finishRecording(); return super.resignFirstResponder() }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignation { NotificationCenter.default.removeObserver(resignation) }
    }
}

struct CaptureShortcutSettings: View {
    @ObservedObject var shortcuts: CaptureShortcuts
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(CaptureShortcuts.actions, id: \.0) { action, title, symbol in
                HStack {
                    if let image = BakerImages.template(symbol, fallback: "viewfinder") { Image(nsImage: image) }
                    Text(title); Spacer()
                    ShortcutRecorder(binding: shortcuts.bindings[action], changed: { shortcuts.set(action, $0) }, recordingChanged: { active in
                        if active { shortcuts.beginRecording() } else { shortcuts.endRecording() }
                    }).frame(width: 175, height: 28)
                    Button { shortcuts.set(action, nil) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).help("Clear shortcut")
                }
            }
            Text("Use Command or Control with a key. Baker shortcuts pause while recording. Escape cancels; Delete clears.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            if let message = shortcuts.message { Text(message).font(BakerTypography.supporting).foregroundStyle(.orange) }
        }
    }
}
