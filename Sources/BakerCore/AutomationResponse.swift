import Darwin
import Foundation

public enum AutomationResponse {
    public static let maximumBytes = 8 * 1024 * 1024

    public static func read(_ url: URL, requestID: UUID) throws -> [String: Any] {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw invalid() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_size >= 0, info.st_size <= maximumBytes else { throw invalid() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = result["id"] as? String, UUID(uuidString: id) == requestID,
              result["ok"] is Bool else { throw invalid() }
        return result
    }

    private static func invalid() -> BakerError {
        BakerError(message: "Baker returned an invalid or oversized response. Inspect status before retrying.", code: .invalidResponse)
    }
}
