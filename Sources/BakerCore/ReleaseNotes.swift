import Foundation

/// Small native release-note blocks; no HTML or remote resources are loaded.
public struct ReleaseNoteBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case heading, paragraph, bullet, code }
    public let kind: Kind
    public let text: String
    public static func parse(_ markdown: String) -> [Self] {
        var blocks: [Self] = [], paragraph: [String] = [], code: [String] = []
        var inCode = false
        func flush() {
            if !paragraph.isEmpty { blocks.append(Self(kind: .paragraph, text: paragraph.joined(separator: " "))); paragraph = [] }
        }
        for line in markdown.prefix(12_000).components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                if inCode { blocks.append(Self(kind: .code, text: code.joined(separator: "\n"))); code = [] }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            if ["---", "***", "___"].contains(trimmed) { flush(); continue }
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); blocks.append(Self(kind: .heading, text: String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces))); continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush(); blocks.append(Self(kind: .bullet, text: String(trimmed.dropFirst(2)))); continue
            }
            if trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil {
                flush(); blocks.append(Self(kind: .bullet, text: trimmed)); continue
            }
            if trimmed.hasPrefix("> ") { paragraph.append(String(trimmed.dropFirst(2))) }
            else { paragraph.append(trimmed) }
        }
        flush()
        if inCode && !code.isEmpty { blocks.append(Self(kind: .code, text: code.joined(separator: "\n"))) }
        return blocks
    }
}
