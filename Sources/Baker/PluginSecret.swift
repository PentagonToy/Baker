import Foundation
import Security
import BakerCore

/// Keys never enter preferences, manifests or CLI responses. Only the selected invocation receives one.
enum PluginSecret {
    private static let service = "Baker.OCRPlugin"
    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }
    static func read(_ id: String) throws -> String? {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(q as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw BakerError(message: "Unlock the plugin key in Keychain, then try again.", code: .permissionDenied)
        }
        return value
    }
    static func save(_ value: String, id: String) throws {
        let q = query(id)
        if value.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }; return
        }
        let data = Data(value.utf8)
        let result = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw failure() }
        } else if result != errSecSuccess { throw failure() }
    }
    private static func failure() -> BakerError { BakerError(message: "The plugin key could not be saved in Keychain.", code: .storageFailed) }
}
