import Foundation

public enum DropboxOAuth {
    public static let port: UInt16 = 53683
    public static let redirect = "http://127.0.0.1:53683/oauth/dropbox"
    public static let scopes = "files.metadata.read files.content.read files.content.write"
    public static func authorizationURL(clientID: String, verifier: String, state: String) throws -> URL {
        guard clientID.range(of: #"^[a-z0-9]{8,64}$"#, options: .regularExpression) != nil, state.count >= 32,
              verifier.range(of: #"^[A-Za-z0-9._~-]{43,128}$"#, options: .regularExpression) != nil else { throw BakerError(message: "Set a Dropbox App Key in Settings → Cloud.") }
        var url = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        url.queryItems = ["client_id": clientID, "response_type": "code", "redirect_uri": redirect, "state": state,
            "code_challenge": GoogleOAuth.challenge(verifier), "code_challenge_method": "S256", "token_access_type": "offline", "scope": scopes].map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
}
