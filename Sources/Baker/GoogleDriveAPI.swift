import Foundation
import BakerCore
import Security
import LocalAuthentication
import CryptoKit
import UniformTypeIdentifiers

protocol GoogleTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, fromFile file: URL) async throws -> (Data, URLResponse)
    func download(for request: URLRequest) async throws -> (URL, URLResponse)
}
struct GoogleURLTransport: GoogleTransport {
    let session: URLSession
    init(session: URLSession = GoogleHTTP.session) { self.session = session }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) { try await session.data(for: request) }
    func upload(for request: URLRequest, fromFile file: URL) async throws -> (Data, URLResponse) { try await session.upload(for: request, fromFile: file) }
    func download(for request: URLRequest) async throws -> (URL, URLResponse) { try await session.download(for: request) }
}

struct GoogleTokens: Codable {
    let clientID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var clientSecret: String? = nil
}
struct GoogleTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
    let token_type: String
    let scope: String?
}
enum GoogleHTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()
    static func checked(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let response = response as? HTTPURLResponse else { throw BakerError(message: "Google returned an invalid response.") }
        guard (200...299).contains(response.statusCode) else {
            let message: String
            switch response.statusCode {
            case 400: message = "Google rejected the request. Check the Desktop client configuration and try signing in again."
            case 401: message = "Google authorization expired. Reconnect your account."
            case 403: message = "Google denied access. Check Drive API, OAuth test users and granted file permissions."
            case 404: message = "The Drive file is no longer available. Refresh the list."
            case 429: message = "Google is busy. Wait briefly, then try again."
            default: message = "Google request failed (HTTP \(response.statusCode)). Try again."
            }
            throw BakerError(message: message)
        }
        guard data.count <= 1_048_576 else { throw BakerError(message: "Google response exceeds the metadata limit.") }
        return data
    }
    static func token(fields: [String: String], clientID: String, previousRefresh: String? = nil, transport: any GoogleTransport = GoogleURLTransport()) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleOAuth.form(fields)
        let (data, response) = try await transport.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
            struct Failure: Decodable { let error: String? }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            if failure?.error == "invalid_client" || failure?.error == "unauthorized_client" {
                throw BakerError(message: "Google rejected the Desktop credentials. Import Desktop JSON from Google Console, then reconnect.")
            }
            if failure?.error == "invalid_grant" { throw BakerError(message: "Google login is no longer valid. Reconnect your account.") }
        }
        let result = try JSONDecoder().decode(GoogleTokenResponse.self, from: checked(data, response))
        guard result.token_type.lowercased() == "bearer", !result.access_token.isEmpty, result.access_token.utf8.count < 16_384,
              result.expires_in.isFinite, (1...86400).contains(result.expires_in),
              result.scope.map({ $0.split(separator: " ").contains(Substring(GoogleOAuth.scope)) }) ?? true,
              let refresh = result.refresh_token ?? previousRefresh, !refresh.isEmpty, refresh.utf8.count < 16_384 else {
            throw BakerError(message: "Google did not grant reusable Drive access. Reconnect and allow Baker file access.")
        }
        return GoogleTokens(clientID: clientID, accessToken: result.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(result.expires_in), clientSecret: fields["client_secret"])
    }
}
protocol GoogleCredentialStore {
    func load() throws -> GoogleTokens?
    func save(_ tokens: GoogleTokens) throws
    func remove() throws
}
struct GoogleTokenVault: GoogleCredentialStore {
    var service = "local.baker.app.google-drive"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "oauth"] }
    func load() throws -> GoogleTokens? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw BakerError(message: "Stored Google login is unavailable. Choose Connect to sign in again.") }
        return try JSONDecoder().decode(GoogleTokens.self, from: data)
    }
    func save(_ tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query; request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw BakerError(message: "Could not save Google login in Keychain.") }; return
        }
        guard status == errSecSuccess else { throw BakerError(message: "Could not update Google login in Keychain.") }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BakerError(message: "Could not remove Google login from Keychain.") }
    }
}

struct DriveFile: Decodable, Identifiable {
    let id: String
    let name: String
    let size: String?
    let appProperties: [String: String]?
}
struct DrivePage: Decodable { let files: [DriveFile]; let nextPageToken: String? }
struct GoogleDriveAPI {
    let accessToken: String
    var transport: any GoogleTransport = GoogleURLTransport()
    static func fingerprint(_ file: URL) throws -> String {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size > 0, size <= CaptureArchive.maximumSourceBytes else { throw BakerError(message: "Capture exceeds the upload size limit.") }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256(), total = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation(); total += data.count
            guard total <= CaptureArchive.maximumSourceBytes else { throw BakerError(message: "Capture changed or exceeds the size limit.") }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func request(_ path: String, query: [String: String] = [:], method: String = "GET", json: [String: Any]? = nil, upload: Bool = false) throws -> URLRequest {
        var components = URLComponents(string: "https://www.googleapis.com/" + (upload ? "upload/" : "") + "drive/v3/" + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!); request.httpMethod = method
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        if let json { request.httpBody = try JSONSerialization.data(withJSONObject: json); request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func validID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 256, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw BakerError(message: "Invalid Drive file identifier.") }
        return id
    }
    func list(query: String, page: String? = nil, limit: Int = 100) async throws -> DrivePage {
        var parameters = ["q": "trashed = false and (" + query + ")", "fields": "nextPageToken,files(id,name,size,appProperties)", "pageSize": String(limit), "orderBy": "createdTime desc", "spaces": "drive"]
        if let page { parameters["pageToken"] = page }
        let (data, response) = try await transport.data(for: request("files", query: parameters))
        return try JSONDecoder().decode(DrivePage.self, from: GoogleHTTP.checked(data, response))
    }
    func folder(parent: String? = nil, metadata: Bool = false, create: Bool) async throws -> String? {
        let role = metadata ? "metadata" : "root"
        var q = "mimeType = 'application/vnd.google-apps.folder' and appProperties has { key='bakerRole' and value='\(role)' }"
        if let parent { q += " and '\(try validID(parent))' in parents" }
        let matches = try await list(query: q, limit: 2).files
        if let existing = matches.first { return try validID(existing.id) }
        guard create else { return nil }
        var body: [String: Any] = ["name": metadata ? ".baker" : "Baker", "mimeType": "application/vnd.google-apps.folder", "appProperties": ["bakerRole": role]]
        if let parent { body["parents"] = [try validID(parent)] }
        let (data, response) = try await transport.data(for: request("files", query: ["fields": "id"], method: "POST", json: body))
        struct ID: Decodable { let id: String }
        return try validID(JSONDecoder().decode(ID.self, from: GoogleHTTP.checked(data, response)).id)
    }
    func captures(root: String, page: String? = nil) async throws -> DrivePage {
        try await list(query: "'\(try validID(root))' in parents and appProperties has { key='bakerRole' and value='capture' }", page: page)
    }
    func upload(file: URL, name: String, parent: String, properties: [String: String]) async throws -> String {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let bytes = values.fileSize, bytes > 0, bytes <= CaptureArchive.maximumSourceBytes else { throw BakerError(message: "Choose a regular capture within 128 MB.") }
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var initial = try request("files", query: ["uploadType": "resumable", "fields": "id"], method: "POST",
            json: ["name": name, "parents": [try validID(parent)], "appProperties": properties], upload: true)
        initial.setValue(String(bytes), forHTTPHeaderField: "X-Upload-Content-Length"); initial.setValue(type, forHTTPHeaderField: "X-Upload-Content-Type")
        let (data, response) = try await transport.data(for: initial)
        _ = try GoogleHTTP.checked(data, response)
        guard let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"), let url = URL(string: location), url.scheme == "https", url.host == "www.googleapis.com", url.path.hasPrefix("/upload/drive/") else { throw BakerError(message: "Google did not return a valid upload session.") }
        var transfer = URLRequest(url: url); transfer.httpMethod = "PUT"
        transfer.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization"); transfer.setValue(type, forHTTPHeaderField: "Content-Type")
        transfer.setValue(String(bytes), forHTTPHeaderField: "Content-Length")
        let (uploaded, completed) = try await transport.upload(for: transfer, fromFile: file)
        struct ID: Decodable { let id: String }
        return try validID(JSONDecoder().decode(ID.self, from: GoogleHTTP.checked(uploaded, completed)).id)
    }
    func download(_ file: DriveFile, maximumBytes: Int = CaptureArchive.maximumSourceBytes) async throws -> URL {
        guard let size = file.size.flatMap(Int.init), size > 0, size <= maximumBytes else { throw BakerError(message: "Drive file is outside the supported download size.") }
        let request = try request("files/" + validID(file.id), query: ["alt": "media"])
        let (temporary, response) = try await transport.download(for: request)
        do {
            _ = try GoogleHTTP.checked(Data(), response)
            let actual = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard actual > 0, actual <= maximumBytes else { throw BakerError(message: "Drive file exceeds the download limit.") }
            return temporary
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
}
