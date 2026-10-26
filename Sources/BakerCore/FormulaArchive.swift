import Foundation
import CryptoKit

public struct FormulaDiagnostics: Codable, Equatable, Sendable {
    public let tokenCount: Int
    public let minimumTokenProbability: Double
    public let ambiguousTokenCount: Int
    public init(tokenCount: Int, minimumTokenProbability: Double, ambiguousTokenCount: Int) {
        self.tokenCount = tokenCount; self.minimumTokenProbability = minimumTokenProbability; self.ambiguousTokenCount = ambiguousTokenCount
    }
}

public struct SavedFormula: Codable, Equatable, Sendable {
    public let savedAt: Date?
    public let id: UUID
    public let originalLatex: String
    public let latex: String
    public let unicodeOverride: String?
    public let unicodeText: String?
    public let model: String
    public let confidenceMethod: String?
    public let confidence: Double?
    public let originalConfidence: Double?
    public let diagnostics: FormulaDiagnostics?
    public let format: String
    public let style: String
    public init(id: UUID, originalLatex: String, latex: String, unicodeOverride: String?, model: String, confidenceMethod: String?, confidence: Double?, diagnostics: FormulaDiagnostics?, format: String, style: String, unicodeText: String? = nil, originalConfidence: Double? = nil, savedAt: Date? = Date()) {
        self.savedAt = savedAt
        self.originalConfidence = originalConfidence
        self.unicodeText = unicodeText
        self.id = id; self.originalLatex = originalLatex; self.latex = latex; self.unicodeOverride = unicodeOverride
        self.model = model; self.confidenceMethod = confidenceMethod; self.confidence = confidence; self.diagnostics = diagnostics; self.format = format; self.style = style
    }
    public var matchesSearchText: String { originalLatex + "\n" + latex + "\n" + (unicodeOverride ?? "") + "\n" + (unicodeText ?? "") }
}

/// Small recognition metadata only. Images and rendered previews are never serialised here.
public final class FormulaArchive {
    public static let fileName = ".baker-formulas.json"
    public static let maximumBytes = 16 * 1024 * 1024
    private struct Index: Codable { let version: Int; let formulas: [SavedFormula] }
    private let url: URL
    private var fingerprint: SHA256.Digest?
    public private(set) var formulas: [UUID: SavedFormula] = [:]
    public init(directory: URL) throws {
        url = directory.appendingPathComponent(Self.fileName)
        guard let data = try read() else { return }
        let index = try JSONDecoder().decode(Index.self, from: data)
        guard index.version == 1, index.formulas.count <= CaptureArchive.maximumRecords else { throw BakerError(message: "Unsupported formula history version or size. Images have been preserved.", code: .storageFailed) }
        for formula in index.formulas {
            guard Self.valid(formula), formulas[formula.id] == nil else { throw BakerError(message: "Invalid formula history. Images have been preserved.", code: .storageFailed) }
            formulas[formula.id] = formula
        }
        fingerprint = SHA256.hash(data: data)
    }
    public func save(_ formula: SavedFormula) throws {
        guard Self.valid(formula) else { throw BakerError(message: "Formula metadata exceeds its supported limits.", code: .resourceLimit) }
        var updated = formulas; updated[formula.id] = formula
        try persist(updated)
    }
    public func retain(_ identifiers: Set<UUID>) throws {
        let updated = formulas.filter { identifiers.contains($0.key) }
        if updated != formulas { try persist(updated) }
    }
    private func persist(_ updated: [UUID: SavedFormula]) throws {
        guard try read().map({ SHA256.hash(data: $0) }) == fingerprint else { throw BakerError(message: "Formula history changed outside Baker. Reopen Baker before saving results.", code: .storageConflict) }
        guard updated.count <= CaptureArchive.maximumRecords else { throw BakerError(message: "Formula history is full.", code: .storageFailed) }
        let data = try JSONEncoder().encode(Index(version: 1, formulas: updated.values.sorted { $0.id.uuidString < $1.id.uuidString }))
        guard data.count <= Self.maximumBytes else { throw BakerError(message: "Formula history reached its 16 MB metadata limit. Existing results have been kept.", code: .resourceLimit) }
        try data.write(to: url, options: .atomic)
        formulas = updated; fingerprint = SHA256.hash(data: data)
    }
    private func read() throws -> Data? {
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumBytes else { throw BakerError(message: "Formula history must be a regular file within 16 MB.", code: .storageFailed) }
        return try Data(contentsOf: url)
    }
    private static func valid(_ value: SavedFormula) -> Bool {
        func probability(_ x: Double) -> Bool { x.isFinite && (0...1).contains(x) }
        guard value.savedAt?.timeIntervalSinceReferenceDate.isFinite ?? true, !value.originalLatex.isEmpty, !value.latex.isEmpty,
              [value.originalLatex, value.latex, value.unicodeOverride ?? "", value.unicodeText ?? ""].allSatisfy({ $0.utf8.count <= 32_768 }),
              [value.model, value.confidenceMethod ?? "", value.format, value.style].allSatisfy({ $0.utf8.count <= 256 }),
              (value.originalConfidence.map(probability) ?? true), value.confidence.map(probability) ?? true else { return false }
        if value.originalConfidence != nil, value.confidenceMethod != "geometric_mean_token_probability_v1" { return false }
        if value.confidence != nil {
            guard value.confidenceMethod == "geometric_mean_token_probability_v1", value.originalLatex == value.latex else { return false }
        }
        if let d = value.diagnostics {
            guard (1...512).contains(d.tokenCount), (0...d.tokenCount).contains(d.ambiguousTokenCount), probability(d.minimumTokenProbability) else { return false }
        }
        return true
    }
}
