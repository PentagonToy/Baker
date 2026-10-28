import AppKit
import BakerCore
import ImageIO

struct StoredCapture: @unchecked Sendable {
    let record: CaptureRecord
    let thumbnail: CGImage
}

/// Serial disk and image work stays off the interface thread.
actor CaptureStore {
    nonisolated let directory: URL
    private var archive: CaptureArchive?
    private var formulaArchive: FormulaArchive?
    private func formulas() throws -> FormulaArchive {
        _ = try opened()
        if let formulaArchive { return formulaArchive }
        let value = try FormulaArchive(directory: directory); formulaArchive = value; return value
    }
    func search(_ query: String) throws -> Set<UUID> {
        let records = try opened().records
        let values = try formulas().formulas
        return Set(records.compactMap { record in
            record.fileName.localizedCaseInsensitiveContains(query) || (values[record.id]?.matchesSearchText.localizedCaseInsensitiveContains(query) ?? false) ? record.id : nil
        })
    }
    func savedFormulas() throws -> [UUID: SavedFormula] { try formulas().formulas }
    func saveFormula(_ value: SavedFormula) throws {
        guard try opened().records.contains(where: { $0.id == value.id }) else { throw BakerError(message: "Formula capture is missing from history.", code: .storageFailed) }
        try formulas().save(value)
    }
    func maintainFormulas(limit: Int, days: Int, now: Date = Date()) throws -> [UUID: SavedFormula] {
        let archive = try formulas(), records = try opened().records
        let cutoff = days > 0 ? now.addingTimeInterval(-Double(days) * 86400) : .distantPast
        func date(_ record: CaptureRecord) -> Date { archive.formulas[record.id]?.savedAt ?? record.createdAt }
        let kept = records.filter { date($0) >= cutoff && archive.formulas[$0.id] != nil }.sorted { date($0) > date($1) }.prefix(max(1, min(500, limit)))
        try archive.retain(Set(kept.map(\.id)))
        return archive.formulas
    }
    func clearFormulas() throws { try formulas().retain([]) }
    func removeFormulas(_ ids: Set<UUID>) throws -> [UUID: SavedFormula] {
        let archive = try formulas()
        try archive.retain(Set(archive.formulas.keys).subtracting(ids))
        return archive.formulas
    }
    func replace(image: CGImage, record: CaptureRecord) throws -> StoredCapture {
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-edited-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, "public.png" as CFString, 1, nil) else { throw BakerError(message: "Could not prepare the edited capture.", code: .storageFailed) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "Could not encode the edited capture.", code: .storageFailed) }
        let archive = try opened(), formulas = try formulas(), previous = formulas.formulas[record.id]
        try formulas.retain(Set(formulas.formulas.keys).subtracting([record.id]))
        let updated: CaptureRecord
        do { updated = try archive.replace(source: temporary, record: record) }
        catch { if let previous { try? formulas.save(previous) }; throw error }
        return StoredCapture(record: updated, thumbnail: try archive.thumbnail(for: updated))
    }
    func replace(vector: CaptureSVG, record: CaptureRecord) throws -> StoredCapture {
        try Task.checkCancellation()
        let thumbnail = try vector.raster(maximumPixelSize: 600)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-edited-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try vector.data.write(to: temporary, options: .atomic)
        let archive = try opened(), formulas = try formulas(), previous = formulas.formulas[record.id]
        try formulas.retain(Set(formulas.formulas.keys).subtracting([record.id]))
        do { return StoredCapture(record: try archive.replace(source: temporary, record: record), thumbnail: thumbnail) }
        catch { if let previous { try? formulas.save(previous) }; throw error }
    }
    init(directory: URL) { self.directory = directory }
    private func opened() throws -> CaptureArchive {
        if let archive { return archive }
        let value = try CaptureArchive(directory: directory)
        archive = value
        return value
    }
    func prepareLocation() throws {
        _ = try opened(); _ = try formulas()
        let presets = directory.appendingPathComponent("Presets", isDirectory: true)
        try FileManager.default.createDirectory(at: presets, withIntermediateDirectories: true)
        let probe = directory.appendingPathComponent(".baker-write-check-\(UUID().uuidString)")
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }
    func records() throws -> [CaptureRecord] { try opened().records }
    func add(file: URL, asFormula: Bool = false) throws -> StoredCapture {
        try Task.checkCancellation()
        let archive = try opened()
        let record = try archive.add(source: file, asFormula: asFormula)
        return StoredCapture(record: record, thumbnail: try archive.thumbnail(for: record))
    }
    func add(image: CGImage, asFormula: Bool = false) throws -> StoredCapture {
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-capture-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, "public.png" as CFString, 1, nil) else {
            throw BakerError(message: "Could not prepare the captured image.", code: .storageFailed)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "Could not encode the captured image.", code: .storageFailed) }
        do {
            let result = try add(file: temporary, asFormula: asFormula)
            try? FileManager.default.removeItem(at: temporary)
            return result
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: temporary)
            throw CancellationError()
        } catch {
            let cause = BakerError.wrapping(error, fallback: .storageFailed)
            throw BakerError(message: "\(cause.userDescription) Original retained at \(temporary.path)", code: cause.code, diagnostic: cause.diagnostic, recovery: cause.recovery)
        }
    }
    func vector(_ record: CaptureRecord) throws -> CaptureSVG {
        guard record.isVector, try opened().records.contains(record) else { throw BakerError(message: "The saved vector capture changed.", code: .storageConflict) }
        let url = try opened().fileURL(for: record)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= CaptureSVG.maximumBytes else {
            throw BakerError(message: "The saved vector capture is unavailable or too large.", code: .storageFailed)
        }
        let value = try CaptureSVG(data: Data(contentsOf: url))
        guard value.width == record.pixelWidth, value.height == record.pixelHeight else { throw BakerError(message: "The saved vector dimensions changed.", code: .storageConflict) }
        return value
    }
    func original(_ record: CaptureRecord) throws -> CGImage {
        try Task.checkCancellation()
        return try opened().original(for: record)
    }
    func preview(_ record: CaptureRecord) throws -> CGImage {
        try Task.checkCancellation()
        return try opened().preview(for: record)
    }
    func thumbnail(_ record: CaptureRecord) throws -> CGImage {
        try Task.checkCancellation()
        return try opened().thumbnail(for: record)
    }
}

extension CaptureStore {
    func recordings() throws -> [RecordingRecord] { try RecordingArchive(directory: directory).records() }
    func addRecording(_ source: URL) throws -> RecordingRecord { try RecordingArchive(directory: directory).add(source) }
    func recordingThumbnail(_ record: RecordingRecord) throws -> CGImage { try RecordingArchive(directory: directory).thumbnail(record) }
}


extension CaptureStore {
    func reconcileHistory() throws -> [CaptureRecord] {
        let store = try opened()
        let records = try store.reconcile()
        // Reload metadata before reconciliation so another app instance's edits are respected.
        formulaArchive = nil
        try formulas().retain(Set(records.map(\.id)))
        return records
    }
    func retentionCandidates(_ policy: CaptureRetentionPolicy) throws -> [CaptureRemovalCandidate] {
        try Task.checkCancellation()
        let records = try reconcileHistory()
        return try policy.expired(in: records).map { record in
            let values = try opened().fileURL(for: record).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values.fileSize else { throw BakerError(message: "A capture size could not be read.", code: .storageFailed) }
            return CaptureRemovalCandidate(record: record, bytes: size, modified: values.contentModificationDate)
        }
    }
    func trashCaptures(_ candidates: [CaptureRemovalCandidate], trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        try Task.checkCancellation()
        _ = try opened().reconcile(trashing: candidates, trash: trash)
        _ = try reconcileHistory()
    }
    func trashCapture(_ record: CaptureRecord, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let url = try opened().fileURL(for: record)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let bytes = values.fileSize else { throw BakerError(message: "The capture size could not be read.", code: .storageFailed) }
        try trashCaptures([CaptureRemovalCandidate(record: record, bytes: bytes, modified: values.contentModificationDate)], trash: trash)
    }
}
