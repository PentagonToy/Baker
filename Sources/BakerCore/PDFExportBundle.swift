import CryptoKit
import Foundation

/// Move a document and its owned figure directory together, rolling back assets if file placement fails.
public enum PDFExportBundle {
    public static func filesForCopy(_ document: URL) -> [URL] {
        let manifest = document.deletingLastPathComponent().appendingPathComponent(document.lastPathComponent + ".baker-assets.json")
        guard let data = try? Data(contentsOf: manifest), let name = try? JSONDecoder().decode(String.self, from: data),
              name.hasPrefix("baker-assets-"), name.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else { return [document] }
        let assets = document.deletingLastPathComponent().appendingPathComponent(name)
        guard let values = try? assets.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isDirectory == true, values.isSymbolicLink != true else { return [document] }
        return [document, assets, manifest]
    }

    /// Reserve a fresh name so automatic exports never replace an existing document.
    public static func saveUnique(source: URL, directory: URL) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let zippedTex = source.lastPathComponent.lowercased().hasSuffix(".tex.zip")
        let ext = zippedTex ? "tex.zip" : source.pathExtension
        let stem = zippedTex ? String(source.lastPathComponent.dropLast(8)) : source.deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            try Task.checkCancellation()
            let name = stem + (index == 1 ? "" : "-\(index)") + (ext.isEmpty ? "" : "." + ext)
            let destination = directory.appendingPathComponent(name)
            // Existing sidecar ownership also reserves this name.
            if files.fileExists(atPath: destination.path + ".baker-assets.json") { continue }
            do { try Data().write(to: destination, options: .withoutOverwriting) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
            do {
                if ["md", "tex"].contains(source.pathExtension.lowercased()) { try save(source: source, destination: destination) }
                else {
                    let stage = directory.appendingPathComponent(".baker-copy-" + UUID().uuidString)
                    defer { try? files.removeItem(at: stage) }
                    try files.copyItem(at: source, to: stage)
                    _ = try files.replaceItemAt(destination, withItemAt: stage)
                }
                return destination
            }
            catch { try? files.removeItem(at: destination); throw error }
        }
        throw BakerError(message: "Choose another save folder or rename existing exports.", code: .storageConflict)
    }

    public static func save(source: URL, destination: URL) throws {
        let files = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".baker-export-" + UUID().uuidString)
        let backup = parent.appendingPathComponent(".baker-assets-backup-" + UUID().uuidString)
        defer { try? files.removeItem(at: stage) }
        try files.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var contents = try Data(contentsOf: source)
        let sourceAssets = source.deletingLastPathComponent().appendingPathComponent("assets")
        // A previously saved file references its own sidecar; read only Baker's small ownership manifest.
        let sourceManifest = source.deletingLastPathComponent().appendingPathComponent(source.lastPathComponent + ".baker-assets.json")
        var assets: URL? = files.fileExists(atPath: sourceAssets.path) ? sourceAssets : nil
        var previousName = "assets"
        if assets == nil, let data = try? Data(contentsOf: sourceManifest), let name = try? JSONDecoder().decode(String.self, from: data),
           name.hasPrefix("baker-assets-"), name.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil {
            assets = source.deletingLastPathComponent().appendingPathComponent(name); previousName = name
        }
        let suffix = SHA256.hash(data: Data(destination.lastPathComponent.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let assetName = "baker-assets-" + suffix
        let targetAssets = parent.appendingPathComponent(assetName)
        let targetManifest = parent.appendingPathComponent(destination.lastPathComponent + ".baker-assets.json")
        var replacedAssets = false, installedAssets = false, committed = false, changedManifest = false
        let oldManifest = try? Data(contentsOf: targetManifest)
        defer {
            if committed { try? files.removeItem(at: backup) }
            else {
                if installedAssets { try? files.removeItem(at: targetAssets) }
                if replacedAssets { try? files.moveItem(at: backup, to: targetAssets) }
                if changedManifest {
                    if let oldManifest { try? oldManifest.write(to: targetManifest, options: .atomic) }
                    else { try? files.removeItem(at: targetManifest) }
                }
            }
        }
        if let assets {
            guard try assets.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw BakerError(message: "Figure assets must not be symbolic links.", code: .exportFailed) }
            guard let entries = files.enumerator(at: assets, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else { throw BakerError(message: "Figure assets are unavailable.", code: .exportFailed) }
            var total = 0
            for case let file as URL in entries {
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { throw BakerError(message: "Figure assets contain a symbolic link.", code: .exportFailed) }
                total += values.fileSize ?? 0
                guard total <= 512 * 1_024 * 1_024 else { throw BakerError(message: "Figure assets exceed the export size limit.", code: .exportFailed) }
            }
            let stagedAssets = stage.appendingPathComponent(assetName)
            try files.copyItem(at: assets, to: stagedAssets)
            let text = String(decoding: contents, as: UTF8.self)
            contents = Data(text.replacingOccurrences(of: "](" + previousName + "/", with: "](" + assetName + "/")
                .replacingOccurrences(of: "{" + previousName + "/", with: "{" + assetName + "/").utf8)
            if files.fileExists(atPath: targetAssets.path) {
                guard let existing = try? Data(contentsOf: targetManifest), (try? JSONDecoder().decode(String.self, from: existing)) == assetName else {
                    throw BakerError(message: "The figure folder is already in use by another document.", code: .storageConflict)
                }
                try files.moveItem(at: targetAssets, to: backup); replacedAssets = true
            }
            try files.moveItem(at: stagedAssets, to: targetAssets); installedAssets = true
        }
        let stagedFile = stage.appendingPathComponent("document")
        try contents.write(to: stagedFile)
        if assets != nil {
            changedManifest = true
            try JSONEncoder().encode(assetName).write(to: targetManifest, options: .atomic)
        }
        if files.fileExists(atPath: destination.path) { _ = try files.replaceItemAt(destination, withItemAt: stagedFile) }
        else { try files.moveItem(at: stagedFile, to: destination) }
        committed = true
    }
}
