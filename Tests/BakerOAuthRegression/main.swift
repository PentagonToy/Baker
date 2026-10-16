import Foundation
import BakerCore

var checks = 0
func check(_ condition: Bool, _ label: String) {
    guard condition else { fatalError("FAIL: " + label) }; checks += 1
}
func reject(_ label: String, _ body: () throws -> Void) {
    do { try body(); fatalError("FAIL: expected rejection: " + label) } catch { checks += 1 }
}
let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
check(GoogleOAuth.challenge(verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 S256 vector")
let state = String(repeating: "s", count: 43)
let url = try GoogleOAuth.authorizationURL(clientID: "123-test.apps.googleusercontent.com", port: 49152, verifier: verifier, state: state)
let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
check(fields["code_challenge_method"] == "S256" && fields["access_type"] == "offline", "PKCE and reusable access")
check(fields["scope"] == GoogleOAuth.scope && fields["redirect_uri"] == "http://127.0.0.1:49152/oauth/google", "limited Drive scope and loopback URI")
check(try GoogleOAuth.callback("/oauth/google?state=\(state)&code=a%2Bb", port: 49152, state: state) == "a+b", "encoded authorization code preserved")
for target in ["/wrong?state=\(state)&code=x", "/oauth/google?state=wrong&code=x", "/oauth/google?state=\(state)&state=\(state)&code=x", "/oauth/google?state=\(state)&code=a&code=b", "/oauth/google?state=\(state)", "/oauth/google?state=\(state)&code=x#fragment"] {
    reject("invalid callback") { _ = try GoogleOAuth.callback(target, port: 49152, state: state) }
}
do { _ = try GoogleOAuth.callback("/oauth/google?state=\(state)&error=access_denied", port: 49152, state: state); fatalError("denial accepted") }
catch is GoogleOAuth.Declined { checks += 1 }
for id in ["", "not-a-client", "https://evil.example/apps.googleusercontent.com"] {
    reject("invalid client") { _ = try GoogleOAuth.authorizationURL(clientID: id, port: 1, verifier: verifier, state: state) }
}
reject("invalid verifier") { _ = try GoogleOAuth.authorizationURL(clientID: "123-test.apps.googleusercontent.com", port: 1, verifier: String(repeating: " ", count: 43), state: state) }
let nonce1 = try GoogleOAuth.random(), nonce2 = try GoogleOAuth.random()
check(nonce1.count == 43 && nonce1 != nonce2 && !nonce1.contains("="), "secure random unpadded nonce")
check(String(data: GoogleOAuth.form(["q": "a+b &c"]), encoding: .utf8) == "q=a%2Bb%20%26c", "form encoding retains special characters")
let dropboxURL = try DropboxOAuth.authorizationURL(clientID: "testappkey12345", verifier: verifier, state: state)
let dropboxFields = Dictionary(uniqueKeysWithValues: URLComponents(url: dropboxURL, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
check(dropboxURL.host == "www.dropbox.com" && dropboxFields["token_access_type"] == "offline", "Dropbox offline browser login")
check(dropboxFields["code_challenge"] == GoogleOAuth.challenge(verifier) && dropboxFields["client_secret"] == nil, "Dropbox uses PKCE without app secret")
check(dropboxFields["redirect_uri"] == DropboxOAuth.redirect && dropboxFields["scope"] == DropboxOAuth.scopes, "Dropbox callback and minimal file scopes")
check(try GoogleOAuth.callback("/oauth/dropbox?state=\(state)&code=test", port: DropboxOAuth.port, state: state, path: "/oauth/dropbox") == "test", "Dropbox callback code")
reject("provider callback mismatch") { _ = try GoogleOAuth.callback("/oauth/google?state=\(state)&code=test", port: DropboxOAuth.port, state: state, path: "/oauth/dropbox") }
print("BakerOAuthRegression: \(checks) checks passed")
