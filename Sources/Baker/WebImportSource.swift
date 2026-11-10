import CoreFoundation
import Foundation
import Network

enum WebImportError: LocalizedError {
    case invalidURL, unavailable, browserRequired, tooLarge, unsupported, pdf, empty, conversion, pdfExport

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a public HTTP or HTTPS link."
        case .unavailable: "Baker couldn’t open this page."
        case .browserRequired: "This site needs a browser to continue."
        case .tooLarge: "Web pages support up to 4 MB. Try a smaller page."
        case .unsupported: "Choose a link to a web page or PDF."
        case .pdf: "Download the PDF and add it to Clipboard & Files to convert it."
        case .empty: "No readable content was found on this page."
        case .conversion: "Baker couldn’t prepare this web page."
        case .pdfExport: "Baker couldn’t create a PDF from this page."
        }
    }
}

enum WebImportSource: Sendable {
    case link(String), html(String, baseURL: URL? = nil)

    static let limit = 4 * 1_024 * 1_024

    func read() async throws -> (html: String, baseURL: URL?, extractArticle: Bool) {
        switch self {
        case let .link(link):
            let (html, url) = try await Self.fetch(link)
            return (html, url, true)
        case let .html(html, baseURL):
            guard html.utf8.count <= Self.limit else { throw WebImportError.tooLarge }
            return (html, baseURL, baseURL != nil)
        }
    }

    private static func fetch(_ link: String) async throws -> (String, URL) {
        guard var url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw WebImportError.invalidURL }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: StopRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        for _ in 0...5 {
            try Task.checkCancellation()
            try validatePublicURL(url)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw WebImportError.unavailable }
            if [301, 302, 303, 307, 308].contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let target = URL(string: location, relativeTo: url)?.absoluteURL {
                url = target
                continue
            }
            if requiresBrowser(http) { throw WebImportError.browserRequired }
            guard (200..<300).contains(http.statusCode) else { throw WebImportError.unavailable }
            if http.mimeType == "application/pdf" { throw WebImportError.pdf }
            guard ["text/html", "application/xhtml+xml"].contains(http.mimeType ?? "") else { throw WebImportError.unsupported }
            guard http.expectedContentLength <= limit else { throw WebImportError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw WebImportError.tooLarge }
                data.append(byte)
            }
            return (decode(data, encodingName: http.textEncodingName), url)
        }
        throw WebImportError.unavailable
    }

    static func requiresBrowser(_ response: HTTPURLResponse) -> Bool {
        [401, 403, 429].contains(response.statusCode)
            || response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
    }

    static func validatePublicURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.user == nil, url.password == nil,
              let host = url.host(percentEncoded: false)?.lowercased(),
              host.contains(".") || host.contains(":") else { throw WebImportError.invalidURL }
        let hostname = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard ![".localhost", ".local", ".internal", ".home.arpa"].contains(where: hostname.hasSuffix),
              !hostname.contains("%") else { throw WebImportError.invalidURL }

        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, nil, &list) == 0, let first = list else { throw WebImportError.unavailable }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            let info = entry.pointee
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(info.ai_addr, info.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0,
                  isPublicAddress(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            else { throw WebImportError.invalidURL }
            current = info.ai_next
        }
    }

    private static func isPublicAddress(_ address: String) -> Bool {
        if let ip = IPv4Address(address) {
            let bytes = [UInt8](ip.rawValue)
            let a = bytes[0], b = bytes[1]
            return !([0, 10, 127].contains(a) || a >= 224
                || (a == 100 && (64...127).contains(b))
                || (a == 169 && b == 254)
                || (a == 172 && (16...31).contains(b))
                || (a == 192 && (b == 168 || (b == 0 && bytes[2] == 0)))
                || (a == 198 && [18, 19].contains(b)))
        }
        guard let ip = IPv6Address(address) else { return false }
        let bytes = [UInt8](ip.rawValue)
        return bytes[0] & 0xe0 == 0x20 && !(bytes[0] == 0x20 && bytes[1] == 0x02)
    }

    private static func decode(_ data: Data, encodingName: String?) -> String {
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]),
           let value = String(data: data, encoding: .utf16) { return value }
        if let encodingName {
            let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if encoding != kCFStringEncodingInvalidId,
               let value = String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) {
                return value
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }
}

private final class StopRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
