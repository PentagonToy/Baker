import Foundation
import CryptoKit

public enum ModelIntegrity {
    public static func verify(_ url: URL, bytes: Int, sha256: String) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == bytes else { throw BakerError(message: "The downloaded model has an unexpected size.", code: .integrityFailed) }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else { throw BakerError(message: "The downloaded model failed its integrity check. Please retry.", code: .integrityFailed) }
    }
}
