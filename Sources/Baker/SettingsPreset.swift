import Foundation
import BakerCore

/// Portable preferences only: no paths, credentials, models or captured content.
struct SettingsPreset: Codable, Equatable {
    var version = 1
    let copyImages: Bool
    let copyText: Bool
    let openTextEditor: Bool
    let captureSounds: Bool
    let hideDesktopIcons: Bool
    let visibleCaptures: Int
    let formulaHistoryLimit: Int
    let formulaHistoryDays: Int
    let mathFont: String
    let languages: [String]
    let formulaFormat: String
    let latexStyle: String

    func validate() throws {
        guard version == 1, (1...5).contains(visibleCaptures), (1...500).contains(formulaHistoryLimit),
              [0, 10, 30].contains(formulaHistoryDays), MathFont(rawValue: mathFont) != nil,
              !languages.isEmpty, languages.count <= OCRLanguages.maximumActive,
              Set(languages).count == languages.count,
              languages.allSatisfy({ code in OCRLanguages.choices.contains { $0.0 == code } }),
              let format = OutputFormat(rawValue: formulaFormat), format != .text,
              LatexCopyStyle(rawValue: latexStyle) != nil else {
            throw BakerError(message: "This preset contains unsupported settings. Your preferences have not changed.", code: .invalidInput)
        }
    }
    static func read(_ url: URL) throws -> SettingsPreset {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 65_536 else {
            throw BakerError(message: "Choose a Baker preset file smaller than 64 KB.", code: .invalidInput)
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536 else { throw BakerError(message: "Choose a Baker preset file smaller than 64 KB.", code: .invalidInput) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
}
