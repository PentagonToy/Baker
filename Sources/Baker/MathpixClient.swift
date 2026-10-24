import Foundation
import Security
import PDFKit
import BakerCore

/// A user-owned Snip session, separate from Mathpix's developer API credentials.
actor MathpixClient {
    struct Session: Codable { let email: String; let token: String }
    enum Failure: LocalizedError {
        case login, quota, rejected(Int), invalidResponse, keychain(OSStatus), expired
        var errorDescription: String? {
            switch self {
            case .login: return "Mathpix sign-in failed. Check your email and password. SSO-only accounts need a Mathpix password."
            case .quota: return "Your Mathpix plan limit was reached. Choose Baker or review your Mathpix account. Extra usage was not enabled."
            case .rejected(let status): return "Mathpix could not complete the request (HTTP \(status)). Choose Baker or try again later."
            case .invalidResponse: return "Mathpix returned an incomplete or unsupported result."
            case .keychain: return "Mathpix could not access its saved session in Keychain. Sign in again or unlock access."
            case .expired: return "Your Mathpix session expired. Sign in again in Settings → Advanced, or choose Baker."
            }
        }
    }
    private var account: Session?
    private let network: URLSession
    private static let service = "local.baker.mathpix"
    init(network: URLSession? = nil, session: Session? = nil) {
        account = session
        if let network { self.network = network }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 180
            self.network = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        }
    }
    deinit { network.invalidateAndCancel() }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private func query(interactive: Bool) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
         kSecAttrAccount as String: "snip-session", kSecUseAuthenticationUI as String: interactive ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
    }
    func restore(interactive: Bool = false) throws -> String? {
        var lookup = query(interactive: interactive)
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw Failure.keychain(status) }
        let session = try JSONDecoder().decode(Session.self, from: data)
        guard !session.token.isEmpty else { throw Failure.invalidResponse }
        account = session; return session.email
    }
    func login(email: String, password: String) async throws -> String {
        guard !email.isEmpty, !password.isEmpty else { throw Failure.login }
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await request("/v1/user/login", method: "POST", body: body, contentType: "application/json", authenticated: false)
        let result = try object(data)
        guard let token = result["token"] as? String, !token.isEmpty else { throw Failure.invalidResponse }
        try Task.checkCancellation()
        let session = Session(email: email, token: token), encoded = try JSONEncoder().encode(session)
        let lookup = query(interactive: true)
        var status = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: encoded] as CFDictionary)
        if status == errSecItemNotFound {
            var item = lookup; item[kSecValueData as String] = encoded
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        account = session; return email
    }
    func logout() throws {
        let status = SecItemDelete(query(interactive: true) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
        account = nil
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String? = nil, file: URL? = nil, authenticated: Bool = true, maximumBytes: Int = 64 * 1024 * 1024) async throws -> Data {
        try Task.checkCancellation()
        guard path.hasPrefix("/v1/") else { throw Failure.invalidResponse }
        var request = URLRequest(url: URL(string: "https://api.mathpix.com" + path)!)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Baker Mathpix account integration", forHTTPHeaderField: "User-Agent")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let account else { throw Failure.expired }
            request.setValue("Bearer " + account.token, forHTTPHeaderField: "Authorization")
        }
        let data: Data, response: URLResponse
        do {
            if let file { (data, response) = try await network.upload(for: request, fromFile: file) }
            else { (data, response) = try await network.data(for: request) }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200...201).contains(response.statusCode) else {
            if response.statusCode == 401 { if authenticated { account = nil; throw Failure.expired }; throw Failure.login }
            let errors = (try? object(data)["errors"] as? [[String: Any]]) ?? []
            let quota = errors.contains { ($0["id"] as? String).map { ["snip_max_limit", "pdf_page_max_limit"].contains($0) } == true }
            if quota || response.statusCode == 429 { throw Failure.quota }
            throw Failure.rejected(response.statusCode)
        }
        guard data.count <= maximumBytes else { throw Failure.invalidResponse }
        return data
    }
    private func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidResponse }
        return value
    }
    private func upload(_ source: URL, path: String, mime: String) async throws -> Data {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 128 * 1024 * 1024 else { throw BakerError(message: "Mathpix accepts files up to 128 MB in Baker.", code: .resourceLimit) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baker-mathpix-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("upload"), boundary = "baker-" + UUID().uuidString
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: file), input = try FileHandle(forReadingFrom: source)
        defer { try? output.close(); try? input.close() }
        let filename = mime == "application/pdf" ? "document.pdf" : "capture.png"
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        var copied = 0
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); copied += chunk.count
            guard copied <= 128 * 1024 * 1024 else { throw BakerError(message: "The file grew beyond Mathpix’s 128 MB upload limit.", code: .resourceLimit) }
            try output.write(contentsOf: chunk)
        }
        guard copied == size else { throw BakerError(message: "The input changed while preparing its upload. Try again.", code: .storageConflict) }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8)); try output.close()
        return try await request(path, method: "POST", contentType: "multipart/form-data; boundary=" + boundary, file: file)
    }
    func recognise(_ source: URL) async throws -> FormulaRecognition {
        let result = try object(await upload(source, path: "/v1/snips-multipart", mime: "image/png"))
        guard let text = result["text_display"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidResponse }
        var latex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\\[", "\\]"), ("$$", "$$"), ("\\(", "\\)")] where latex.hasPrefix(open) && latex.hasSuffix(close) {
            latex = String(latex.dropFirst(open.count).dropLast(close.count)); break
        }
        return FormulaRecognition(latex: LatexWhitespace.compact(latex), confidence: nil, model: "Mathpix · Online")
    }
    func convert(source: URL, destination: URL, format: PDFExportFormat, progress: @escaping @Sendable (Int, Int, String) async -> Void) async throws -> PDFConversionReport {
        let pages = PDFDocument(url: source)?.pageCount ?? 0
        guard (1...2000).contains(pages) else { throw BakerError(message: "Choose a readable PDF with up to 2,000 pages.", code: .resourceLimit) }
        let target = format == .latex ? destination.appendingPathExtension("zip") : destination
        guard !FileManager.default.fileExists(atPath: target.path) else { throw BakerError(message: "The output already exists. Choose a new filename.", code: .storageConflict) }
        await progress(0, pages, "Uploading PDF to Mathpix…")
        let response = try object(await upload(source, path: "/v1/pdfs", mime: "application/pdf"))
        guard let pdf = response["pdf"] as? [String: Any], let id = pdf["id"] as? String, id.range(of: "\\A[A-Za-z0-9_-]+\\z", options: .regularExpression) != nil else { throw Failure.invalidResponse }
        let path = "/v1/pdfs/" + id, deadline = Date().addingTimeInterval(1800)
        while true {
            try Task.checkCancellation()
            guard Date() < deadline else { throw BakerError(message: "Mathpix is still processing this PDF. Check it in Mathpix; Baker will not upload it again automatically.", code: .processTimedOut) }
            let status = try object(await request(path))["pdf"] as? [String: Any]
            if status?["status"] as? String == "completed" { break }
            if status?["status"] as? String == "error" { throw Failure.invalidResponse }
            await progress(status?["completed_pages"] as? Int ?? 0, pages, "Converting with Mathpix…")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let data = try await request(path + (format == .latex ? "/tex" : "/mmd"))
        if format == .latex { guard data.starts(with: [0x50, 0x4b]) else { throw Failure.invalidResponse } }
        else { guard String(data: data, encoding: .utf8) != nil else { throw Failure.invalidResponse } }
        try Task.checkCancellation(); try data.write(to: target, options: .withoutOverwriting)
        await progress(pages, pages, "Mathpix conversion ready.")
        return PDFConversionReport(destination: target, format: format, pages: (1...pages).map { PDFPageSummary(pageNumber: $0, source: .structured, blockCount: 0, characterCount: 0, warnings: []) }, bytesWritten: data.count, warnings: ["Converted online with Mathpix. Review the output against the original." + (format == .latex ? " LaTeX is supplied as a .tex.zip project." : " Output uses Mathpix Markdown.")])
    }
}
