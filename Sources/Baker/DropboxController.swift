import AppKit
import BakerCore

struct DropboxFile: Decodable, Identifiable {
    let id: String
    let name: String
    let path_lower: String?
    let size: Int?
    let tag: String
    enum CodingKeys: String, CodingKey { case id, name, path_lower, size; case tag = ".tag" }
    static func validName(_ name: String) -> Bool {
        name.range(of: #"^[a-f0-9-]{36}-[a-f0-9]{64}-[a-f0-9-]{36}\.(png|jpg|tiff|heic|heif|bmp)$"#, options: .regularExpression) != nil
    }
}
struct DropboxPage: Decodable { let entries: [DropboxFile]; let cursor: String; let has_more: Bool }

struct DropboxAPI {
    let token: String
    let transport: any GoogleTransport
    static func checked(_ data: Data, _ response: URLResponse, limit: Int = 1_048_576) throws -> Data {
        guard let response = response as? HTTPURLResponse else { throw BakerError(message: "Dropbox returned an invalid response.") }
        guard (200...299).contains(response.statusCode) else {
            let hint: String
            switch response.statusCode {
            case 401: hint = "Reconnect Dropbox."
            case 403: hint = "Enable file metadata read, content read and content write in Dropbox App Console, then reconnect."
            case 409: hint = "The file or folder has changed. Refresh Dropbox and retry."
            case 429: hint = "Dropbox is busy. Wait briefly and retry."
            default: hint = "Check the app configuration and retry."
            }
            throw BakerError(message: "Dropbox request failed (HTTP \(response.statusCode)). \(hint)")
        }
        guard data.count <= limit else { throw BakerError(message: "Dropbox metadata exceeds its size limit.") }; return data
    }
    static func tokens(fields: [String: String], previousRefresh: String? = nil, transport: any GoogleTransport) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = GoogleOAuth.form(fields)
        let (data, response) = try await transport.data(for: request)
        let result = try JSONDecoder().decode(GoogleTokenResponse.self, from: checked(data, response))
        guard result.token_type.lowercased() == "bearer", !result.access_token.isEmpty, result.access_token.count < 16384,
              let refresh = result.refresh_token ?? previousRefresh, !refresh.isEmpty, refresh.count < 16384,
              result.expires_in.isFinite, (1...86400).contains(result.expires_in) else { throw BakerError(message: "Dropbox did not grant reusable access. Reconnect Dropbox.") }
        return GoogleTokens(clientID: fields["client_id"]!, accessToken: result.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(result.expires_in))
    }
    func request(_ endpoint: String, fields: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/" + endpoint)!)
        request.httpMethod = "POST"; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        let (data, response) = try await transport.data(for: request)
        return try Self.checked(data, response)
    }
    func folder(_ path: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!)
        request.httpMethod = "POST"; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "autorename": false])
        let (data, response) = try await transport.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 409,
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = value["error"] as? [String: Any], error[".tag"] as? String == "path",
           let pathError = error["path"] as? [String: Any], pathError[".tag"] as? String == "conflict",
           let conflict = pathError["conflict"] as? [String: Any], conflict[".tag"] as? String == "folder" { return }
        _ = try Self.checked(data, response)
    }
    func list(cursor: String? = nil) async throws -> DropboxPage {
        let data = try await request(cursor == nil ? "files/list_folder" : "files/list_folder/continue", fields: cursor.map { ["cursor": $0] } ?? ["path": "/Baker", "limit": 100, "recursive": false])
        return try JSONDecoder().decode(DropboxPage.self, from: data)
    }
    func upload(_ file: URL, path: String) async throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard size.isRegularFile == true, size.isSymbolicLink != true, let count = size.fileSize, count > 0, count <= 128 * 1024 * 1024 else { throw BakerError(message: "Dropbox uploads accept regular files up to 128 MiB.") }
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        request.httpMethod = "POST"; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let arguments: [String: Any] = ["path": path, "mode": "add", "autorename": false, "mute": true, "strict_conflict": true]
        request.setValue(String(data: try JSONSerialization.data(withJSONObject: arguments), encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, response) = try await transport.upload(for: request, fromFile: file); _ = try Self.checked(data, response)
    }
    func download(_ path: String, limit: Int) async throws -> URL {
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(String(data: try JSONSerialization.data(withJSONObject: ["path": path]), encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")
        let (file, response) = try await transport.download(for: request)
        do {
            _ = try Self.checked(Data(), response)
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= limit else { throw BakerError(message: "Downloaded Dropbox file exceeds its size limit.") }
            return file
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }
}

@MainActor
final class DropboxController: ObservableObject {
    @Published var appKey: String { didSet { preferences.set(appKey, forKey: "dropboxAppKey") } }
    @Published private(set) var connected = false
    @Published private(set) var working = false
    @Published private(set) var status = "Connect your own Dropbox account. Transfers run on request."
    @Published private(set) var files: [DropboxFile] = []
    @Published private(set) var hasMore = false
    private var cursor: String?
    private var tokens: GoogleTokens?
    private var task: Task<Void, Never>?
    private let auth = GoogleSignIn()
    private let vault: any GoogleCredentialStore
    private let transport: any GoogleTransport
    private let preferences: UserDefaults
    private unowned let model: Workbench
    init(model: Workbench, preferences: UserDefaults = .standard, transport: any GoogleTransport = GoogleURLTransport(), vault: any GoogleCredentialStore = GoogleTokenVault(service: "local.baker.app.dropbox")) {
        self.model = model; self.preferences = preferences; self.transport = transport; self.vault = vault
        appKey = preferences.string(forKey: "dropboxAppKey") ?? ""
        do { if let value = try vault.load(), value.clientID == appKey { tokens = value; connected = true; status = "Connected to Dropbox." } }
        catch { status = "Stored Dropbox login is unavailable. Reconnect Dropbox." }
    }
    func connect() {
        let key = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            self.status = "Approve Dropbox access in your browser…"
            let reply = try await self.auth.authorize(clientID: key, provider: .dropbox)
            let tokens = try await DropboxAPI.tokens(fields: ["client_id": key, "code": reply.code, "code_verifier": reply.verifier, "redirect_uri": reply.redirect, "grant_type": "authorization_code"], transport: self.transport)
            try Task.checkCancellation(); try self.vault.save(tokens)
            self.tokens = tokens; self.connected = true; self.files = []; self.cursor = nil; self.hasMore = false; self.status = "Connected. Upload a capture or refresh Dropbox."
        }
    }
    func disconnect() {
        guard !working else { return }
        do { try vault.remove(); tokens = nil; connected = false; files = []; cursor = nil; hasMore = false; status = "Disconnected locally. Dropbox files remain." }
        catch { status = "Could not remove the Dropbox login from Keychain." }
    }
    private func api() async throws -> DropboxAPI {
        guard var stored = tokens, stored.clientID == appKey.trimmingCharacters(in: .whitespacesAndNewlines) else { throw BakerError(message: "Connect Dropbox first.") }
        if stored.expiresAt.timeIntervalSinceNow < 60 {
            stored = try await DropboxAPI.tokens(fields: ["client_id": stored.clientID, "refresh_token": stored.refreshToken, "grant_type": "refresh_token"], previousRefresh: stored.refreshToken, transport: transport)
            try Task.checkCancellation(); try vault.save(stored); tokens = stored
        }
        return DropboxAPI(token: stored.accessToken, transport: transport)
    }
    func refresh(more: Bool = false) {
        run {
            let api = try await self.api(); try await api.folder("/Baker")
            let page = try await api.list(cursor: more ? self.cursor : nil)
            try Task.checkCancellation()
            let additions = page.entries.filter { $0.tag == "file" && DropboxFile.validName($0.name) && ($0.size ?? Int.max) <= 128 * 1024 * 1024 }
            var seen = Set(more ? self.files.map(\.id) : [])
            self.files = (more ? self.files : []) + additions.filter { seen.insert($0.id).inserted }
            self.cursor = page.cursor; self.hasMore = page.has_more && self.files.count < 1000
            self.status = "\(self.files.count) Dropbox captures."
        }
    }
    func uploadLatest() { if let capture = model.captures.first { upload(capture) } }
    func upload(_ capture: CaptureRecord) {
        run {
            await self.model.flushFormulaHistory(); try Task.checkCancellation()
            let api = try await self.api(); try await api.folder("/Baker"); try await api.folder("/Baker/.baker")
            let source = self.model.captureURL(capture)
            let hashTask = Task.detached { try GoogleDriveAPI.fingerprint(source) }
            let hash = try await withTaskCancellationHandler(operation: { try await hashTask.value }, onCancel: { hashTask.cancel() })
            let base = capture.id.uuidString.lowercased() + "-" + hash + "-" + UUID().uuidString.lowercased()
            let name = base + "." + source.pathExtension.lowercased()
            try await api.upload(source, path: "/Baker/" + name)
            do {
                if let formula = self.model.savedFormulas[capture.id] {
                    let data = try JSONEncoder().encode(formula)
                    guard data.count <= 262144 else { throw BakerError(message: "Formula metadata exceeds 256 KiB.") }
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-dropbox-\(UUID().uuidString).json")
                    try data.write(to: temporary, options: .atomic); defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                    try await api.upload(temporary, path: "/Baker/.baker/" + base + ".json")
                }
                self.status = "Capture and saved formula uploaded to Dropbox."
            } catch is CancellationError { throw CancellationError() }
            catch { self.status = "Image uploaded. Formula metadata failed; upload again to create a complete version." }
        }
    }
    func importCapture(_ file: DropboxFile) {
        run {
            guard DropboxFile.validName(file.name), let size = file.size, size > 0, size <= 128 * 1024 * 1024 else { throw BakerError(message: "Choose a supported Baker capture.") }
            let api = try await self.api()
            let base = (file.name as NSString).deletingPathExtension
            var imports = self.preferences.dictionary(forKey: "dropboxImports") as? [String: String] ?? [:]
            let record: CaptureRecord
            if let id = imports[file.id].flatMap(UUID.init(uuidString:)), let existing = self.model.captures.first(where: { $0.id == id }) {
                record = existing
                if self.model.savedFormulas[id] != nil { self.status = "Already imported. Local formula edits were kept."; return }
            } else {
                let temporary = try await api.download("/Baker/" + file.name, limit: 128 * 1024 * 1024)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let hashTask = Task.detached { try GoogleDriveAPI.fingerprint(temporary) }
                let hash = try await withTaskCancellationHandler(operation: { try await hashTask.value }, onCancel: { hashTask.cancel() })
                guard base.dropFirst(37).prefix(64) == hash else { throw BakerError(message: "Dropbox image does not match its saved fingerprint.") }
                record = try await self.model.importFileIntoHistory(temporary)
                if imports.count >= 10000 { imports = [:] }
                imports[file.id] = record.id.uuidString; self.preferences.set(imports, forKey: "dropboxImports")
            }
            self.status = "Image imported."
            do {
                let metadata = try await api.download("/Baker/.baker/" + base + ".json", limit: 262144)
                defer { try? FileManager.default.removeItem(at: metadata) }
                let formula = try JSONDecoder().decode(SavedFormula.self, from: Data(contentsOf: metadata))
                guard formula.id.uuidString.lowercased() == String(base.prefix(36)) else { throw BakerError(message: "Formula metadata belongs to another capture.") }
                try await self.model.restoreCloudFormula(formula, for: record.id)
                self.status = "Image and formula imported."
            } catch is CancellationError { throw CancellationError() }
            catch { self.status = "Image imported. Formula metadata is absent or unavailable; Import can retry without duplicating the image." }
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working, !model.busy else { return }; working = true; model.busy = true
        task = Task { defer { working = false; model.busy = false; task = nil }
            do { try Task.checkCancellation(); try await operation() }
            catch is CancellationError { status = "Dropbox action cancelled." }
            catch { status = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); auth.cancel() }
    func shutdown() async { cancel(); _ = await task?.value }
}
