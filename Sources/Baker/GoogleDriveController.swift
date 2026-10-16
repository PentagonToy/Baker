import AppKit
import BakerCore
import CryptoKit

@MainActor
final class GoogleDriveController: ObservableObject {
    @Published var clientID: String {
        didSet { preferences.set(clientID, forKey: "googleDriveClientID"); if oldValue != clientID { importedClientSecret = nil } }
    }
    @Published private(set) var connected = false
    @Published private(set) var working = false
    @Published private(set) var status = "Connect to upload and import Baker captures."
    @Published private(set) var files: [DriveFile] = []
    @Published private(set) var hasMore = false
    private var pageToken: String?
    private var rootID: String?
    private var tokens: GoogleTokens?
    private var importedClientSecret: String?
    private var task: Task<Void, Never>?
    private let auth = GoogleSignIn()
    private let vault: any GoogleCredentialStore
    private let preferences: UserDefaults
    private let transport: any GoogleTransport
    private unowned let model: Workbench
    init(model: Workbench, preferences: UserDefaults = .standard, transport: any GoogleTransport = GoogleURLTransport(), vault: any GoogleCredentialStore = GoogleTokenVault()) {
        self.model = model; self.preferences = preferences; self.transport = transport; self.vault = vault
        clientID = preferences.string(forKey: "googleDriveClientID") ?? ""
        do {
            if let stored = try vault.load(), stored.clientID == clientID, !stored.refreshToken.isEmpty {
                tokens = stored; connected = true; status = "Connected · transfers run when requested."
            }
        } catch { status = error.localizedDescription }
    }
    func connect() {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            self.status = "Complete Google sign-in in your browser…"
            let response = try await self.auth.authorize(clientID: id)
            var fields = ["client_id": id, "code": response.code, "code_verifier": response.verifier,
                "redirect_uri": response.redirect, "grant_type": "authorization_code"]
            if let secret = self.importedClientSecret ?? self.tokens?.clientSecret { fields["client_secret"] = secret }
            let tokens = try await GoogleHTTP.token(fields: fields, clientID: id, transport: self.transport)
            try Task.checkCancellation()
            try self.vault.save(tokens)
            self.tokens = tokens; self.connected = true; self.rootID = nil; self.files = []; self.pageToken = nil; self.hasMore = false
            self.status = "Connected to Google Drive. Refresh to see Baker captures."
        }
    }
    func importConfiguration() {
        guard !working, !connected else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 65_536 else { throw BakerError(message: "Choose the Google Desktop client JSON file.") }
            struct Configuration: Decodable { struct Installed: Decodable { let client_id: String; let client_secret: String? }; let installed: Installed }
            let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)).installed
            _ = try GoogleOAuth.authorizationURL(clientID: config.client_id, port: 1, verifier: String(repeating: "a", count: 43), state: String(repeating: "s", count: 32))
            clientID = config.client_id; importedClientSecret = config.client_secret
            status = "Desktop configuration loaded. Choose Connect Google."
        } catch { status = "Could not read a Google Desktop client JSON file." }
    }
    func disconnect() {
        guard !working else { return }
        do {
            try vault.remove(); tokens = nil; importedClientSecret = nil; connected = false; files = []; rootID = nil; pageToken = nil; hasMore = false
            status = "Disconnected. Drive files remain in your account."
        } catch { status = error.localizedDescription }
    }
    private func api() async throws -> GoogleDriveAPI {
        guard var stored = tokens, stored.clientID == clientID.trimmingCharacters(in: .whitespacesAndNewlines) else { throw BakerError(message: "Connect Google Drive first.") }
        if stored.expiresAt.timeIntervalSinceNow < 60 {
            var fields = ["client_id": stored.clientID, "refresh_token": stored.refreshToken, "grant_type": "refresh_token"]
            if let secret = stored.clientSecret { fields["client_secret"] = secret }
            stored = try await GoogleHTTP.token(fields: fields, clientID: stored.clientID, previousRefresh: stored.refreshToken, transport: transport)
            try Task.checkCancellation(); try vault.save(stored); tokens = stored
        }
        return GoogleDriveAPI(accessToken: stored.accessToken, transport: transport)
    }
    func refresh(more: Bool = false) {
        run {
            let api = try await self.api()
            guard let root = try await api.folder(create: false) else {
                self.files = []; self.hasMore = false; self.pageToken = nil; self.status = "No Baker folder yet. Upload a capture to create it."; return
            }
            self.rootID = root
            let page = try await api.captures(root: root, page: more ? self.pageToken : nil)
            try Task.checkCancellation()
            var seen = Set(more ? self.files.map(\.id) : [])
            let additions = page.files.filter { seen.insert($0.id).inserted }
            self.files = more ? self.files + additions : additions
            self.pageToken = page.nextPageToken; self.hasMore = page.nextPageToken != nil && self.files.count < 1000
            self.status = "\(self.files.count) Drive captures · choose Import to keep a local copy."
        }
    }
    func uploadLatest() { if let record = model.captures.first { upload(record) } }
    func upload(_ record: CaptureRecord) {
        run {
            await self.model.flushFormulaHistory()
            try Task.checkCancellation()
            let api = try await self.api()
            guard let root = try await api.folder(create: true) else { return }
            self.rootID = root
            self.status = "Uploading capture…"
            let source = self.model.captureURL(record)
            let hashing = Task.detached { try GoogleDriveAPI.fingerprint(source) }
            let digest = try await withTaskCancellationHandler(operation: { try await hashing.value }, onCancel: { hashing.cancel() })
            try Task.checkCancellation()
            let identifier = record.id.uuidString.lowercased()
            let query = "'\(root)' in parents and appProperties has { key='bakerCaptureID' and value='\(identifier)' } and appProperties has { key='bakerSHA256' and value='\(digest)' } and appProperties has { key='bakerRole' and value='capture' }"
            if try await api.list(query: query, limit: 1).files.isEmpty {
                _ = try await api.upload(file: source, name: record.fileName, parent: root, properties: ["bakerRole": "capture", "bakerCaptureID": identifier, "bakerSHA256": digest])
            }
            if let formula = self.model.savedFormulas[record.id], let folder = try await api.folder(parent: root, metadata: true, create: true) {
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-formula-" + UUID().uuidString + ".json")
                defer { try? FileManager.default.removeItem(at: temporary) }
                let data = try JSONEncoder().encode(formula)
                guard data.count <= 262_144 else { throw BakerError(message: "Image uploaded, but formula metadata exceeds 256 KB.") }
                try data.write(to: temporary, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                _ = try await api.upload(file: temporary, name: identifier + "-" + UUID().uuidString.lowercased() + ".json", parent: folder, properties: ["bakerRole": "formula", "bakerCaptureID": identifier, "bakerSHA256": digest])
            }
            self.status = "Uploaded to Baker in Google Drive. Existing versions were kept."
        }
    }
    func importCapture(_ file: DriveFile) {
        run {
            let imports = self.preferences.dictionary(forKey: "googleDriveImports") as? [String: String] ?? [:]
            let cachedID = imports[file.id].flatMap(UUID.init(uuidString:))
            let cached = self.model.captures.first { $0.id == cachedID }
            if let cached, self.model.savedFormulas[cached.id] != nil {
                self.status = "Already imported. Your local formula edits were kept."; return
            }
            let api = try await self.api()
            let record: CaptureRecord
            if let cached { record = cached }
            else {
                self.status = "Downloading capture…"
                let downloaded = try await api.download(file)
                defer { try? FileManager.default.removeItem(at: downloaded) }
                try Task.checkCancellation()
                if let expected = file.appProperties?["bakerSHA256"] {
                    let hashing = Task.detached { try GoogleDriveAPI.fingerprint(downloaded) }
                    let actual = try await withTaskCancellationHandler(operation: { try await hashing.value }, onCancel: { hashing.cancel() })
                    guard actual == expected else { throw BakerError(message: "Drive image failed its content check. Refresh and try again.") }
                }
                record = try await self.model.importFileIntoHistory(downloaded)
                var updated = imports; updated[file.id] = record.id.uuidString
                if updated.count <= CaptureArchive.maximumRecords { self.preferences.set(updated, forKey: "googleDriveImports") }
            }
            self.status = "Image imported to capture history."
            do {
                guard let originalID = file.appProperties?["bakerCaptureID"], UUID(uuidString: originalID) != nil,
                      let digest = file.appProperties?["bakerSHA256"], digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      let root = self.rootID, let metadata = try await api.folder(parent: root, metadata: true, create: false) else { return }
                let matches = try await api.list(query: "'\(metadata)' in parents and appProperties has { key='bakerRole' and value='formula' } and appProperties has { key='bakerCaptureID' and value='\(originalID)' } and appProperties has { key='bakerSHA256' and value='\(digest)' }", limit: 1).files
                if let match = matches.first {
                    let temporary = try await api.download(match, maximumBytes: 262_144)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let formula = try JSONDecoder().decode(SavedFormula.self, from: Data(contentsOf: temporary))
                    guard formula.id.uuidString.lowercased() == originalID.lowercased() else { throw BakerError(message: "Formula metadata does not match the capture.") }
                    try await self.model.restoreCloudFormula(formula, for: record.id)
                    self.status = "Image and formula imported to capture history."
                }
            } catch is CancellationError { throw CancellationError() }
            catch { self.status = "Image imported; formula metadata could not be restored. Choose Import to retry." }
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working, !model.busy else { return }
        working = true; model.busy = true
        task = Task {
            defer { working = false; model.busy = false; task = nil }
            do { try Task.checkCancellation(); try await operation() }
            catch is CancellationError { status = "Drive action cancelled." }
            catch { status = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); auth.cancel() }
    func shutdown() async { cancel(); _ = await task?.value }
}
