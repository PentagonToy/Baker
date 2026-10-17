import Foundation
import Security

/// Remove only Baker's retired logins, without reading secrets or prompting.
enum LegacyCloudCleanup {
    static func run() {
        let preferences = UserDefaults.standard
        guard !preferences.bool(forKey: "retiredCloudCredentialsRemoved") else { return }
        var completed = true
        for service in ["local.baker.app.google-drive", "local.baker.app.dropbox"] {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: "oauth",
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
            let status = SecItemDelete(query as CFDictionary)
            completed = completed && (status == errSecSuccess || status == errSecItemNotFound)
        }
        for key in ["googleDriveClientID", "googleDriveImports", "dropboxAppKey", "dropboxImports"] { preferences.removeObject(forKey: key) }
        if completed { preferences.set(true, forKey: "retiredCloudCredentialsRemoved") }
    }
}
