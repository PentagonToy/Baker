import Foundation

public enum CaptureLocation {
    /// Move the legacy archive as a unit, preserving IDs and hidden metadata.
    public static func prepare(documents: URL, pictures: URL) throws -> URL {
        let files = FileManager.default
        let target = documents.appendingPathComponent("Baker", isDirectory: true)
        let legacy = pictures.appendingPathComponent("Baker", isDirectory: true)
        if !files.fileExists(atPath: target.path), files.fileExists(atPath: legacy.path) {
            let values = try legacy.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw BakerError(message: "The previous capture folder could not be moved safely. It remains in Pictures/Baker.", code: .storageFailed) }
            try files.createDirectory(at: documents, withIntermediateDirectories: true)
            try files.moveItem(at: legacy, to: target)
        }
        return target
    }
}
