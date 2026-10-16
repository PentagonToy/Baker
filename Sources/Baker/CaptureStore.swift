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
        guard try opened().records.contains(where: { $0.id == value.id }) else { throw BakerError(message: "Formula capture is missing from history.") }
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
    func replace(image: CGImage, record: CaptureRecord) throws -> StoredCapture {
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-edited-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, "public.png" as CFString, 1, nil) else { throw BakerError(message: "Could not prepare the edited capture.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "Could not encode the edited capture.") }
        let archive = try opened(), formulas = try formulas(), previous = formulas.formulas[record.id]
        try formulas.retain(Set(formulas.formulas.keys).subtracting([record.id]))
        let updated: CaptureRecord
        do { updated = try archive.replace(source: temporary, record: record) }
        catch { if let previous { try? formulas.save(previous) }; throw error }
        return StoredCapture(record: updated, thumbnail: try archive.thumbnail(for: updated))
    }
    init(directory: URL) { self.directory = directory }
    private func opened() throws -> CaptureArchive {
        if let archive { return archive }
        let value = try CaptureArchive(directory: directory)
        archive = value
        return value
    }
    func records() throws -> [CaptureRecord] { try opened().records }
    func add(file: URL) throws -> StoredCapture {
        try Task.checkCancellation()
        let archive = try opened()
        let record = try archive.add(source: file)
        return StoredCapture(record: record, thumbnail: try archive.thumbnail(for: record))
    }
    func add(image: CGImage) throws -> StoredCapture {
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-capture-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, "public.png" as CFString, 1, nil) else {
            throw BakerError(message: "Could not prepare the captured image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "Could not encode the captured image.") }
        do {
            let result = try add(file: temporary)
            try? FileManager.default.removeItem(at: temporary)
            return result
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: temporary)
            throw CancellationError()
        } catch {
            throw BakerError(message: "\(error.localizedDescription) Original retained at \(temporary.path)")
        }
    }
    func thumbnail(_ record: CaptureRecord) throws -> CGImage { try opened().thumbnail(for: record) }
}
