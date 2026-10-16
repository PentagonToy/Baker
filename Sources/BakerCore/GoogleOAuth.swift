import Foundation
import CryptoKit
import Security

public enum GoogleOAuth {
    public struct Declined: LocalizedError { public var errorDescription: String? { "Google sign-in was declined. You can try again." }; public init() {} }
    public static let scope = "https://www.googleapis.com/auth/drive.file"
    public static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BakerError(message: "Could not prepare secure Google sign-in.") }
        return base64(Data(bytes))
    }
    public static func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public static func challenge(_ verifier: String) -> String { base64(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public static func authorizationURL(clientID: String, port: UInt16, verifier: String, state: String) throws -> URL {
        guard clientID.range(of: #"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil,
              port > 0, verifier.range(of: #"^[A-Za-z0-9._~-]{43,128}$"#, options: .regularExpression) != nil, state.count >= 32 else { throw BakerError(message: "Set a Google Desktop OAuth Client ID in Settings → Cloud.") }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = ["client_id": clientID, "redirect_uri": redirect(port), "response_type": "code", "scope": scope,
            "code_challenge": challenge(verifier), "code_challenge_method": "S256", "state": state,
            "access_type": "offline", "prompt": "consent"].map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    public static func redirect(_ port: UInt16) -> String { "http://127.0.0.1:\(port)/oauth/google" }
    public static func callback(_ target: String, port: UInt16, state: String, path: String = "/oauth/google") throws -> String {
        guard target.hasPrefix(path + "?"), target.utf8.count <= 8192,
              let url = URLComponents(string: "http://127.0.0.1:\(port)" + target), url.path == path, url.fragment == nil else { throw BakerError(message: "Invalid sign-in callback.") }
        let items = url.queryItems ?? []
        func unique(_ name: String) -> String? { let values = items.filter { $0.name == name }; return values.count == 1 ? values[0].value : nil }
        guard unique("state") == state else { throw BakerError(message: "Sign-in response did not match this request.") }
        if unique("error") != nil { throw Declined() }
        guard let code = unique("code"), !code.isEmpty, code.utf8.count <= 4096 else { throw BakerError(message: "Google did not return an authorization code.") }
        return code
    }
    public static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return Data(fields.sorted { $0.key < $1.key }.map { $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
    }
}
