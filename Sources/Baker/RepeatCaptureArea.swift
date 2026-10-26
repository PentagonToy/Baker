import AppKit
import BakerCore

/// A local rectangle follows its physical display when desktop arrangement changes.
/// A changed display size requires a fresh selection instead of capturing a different area.
struct RepeatCaptureArea: Codable, Equatable {
    var version = 1
    let displayIdentity: String
    let displaySize: CGSize
    let rect: CGRect
    static let preference = PreferenceKeys.repeatCaptureArea.name

    var isValid: Bool {
        version == 1 && !displayIdentity.isEmpty && displayIdentity.count < 128 &&
        displaySize.width.isFinite && displaySize.height.isFinite && displaySize.width > 0 && displaySize.height > 0 &&
        !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite &&
        rect.width >= 2 && rect.height >= 2 && CGRect(origin: .zero, size: displaySize).contains(rect)
    }
    func matches(identity: String, size: CGSize) -> Bool {
        isValid && identity == displayIdentity && size == displaySize
    }
    static func load(defaults: UserDefaults = .standard) -> Self? {
        guard let data = defaults.data(forKey: preference), data.count <= 4096,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.preference)
    }
}

@MainActor extension RepeatCaptureArea {
    static func identity(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    init?(region: CaptureRegion) {
        guard let identity = Self.identity(of: region.screen) else { return nil }
        self.init(displayIdentity: identity, displaySize: region.screen.frame.size, rect: region.rect)
        guard isValid else { return nil }
    }
    func resolve(screens: [NSScreen] = NSScreen.screens) -> CaptureRegion? {
        guard let screen = screens.first(where: { screen in
            guard let identity = Self.identity(of: screen) else { return false }
            return matches(identity: identity, size: screen.frame.size)
        }) else { return nil }
        return CaptureRegion(screen: screen, rect: rect)
    }
}
