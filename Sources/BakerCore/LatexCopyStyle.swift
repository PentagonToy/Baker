import Foundation

/// Wrappers change the paste format without rewriting the recognised expression.
public enum LatexCopyStyle: String, CaseIterable, Sendable {
    case bare = "Bare LaTeX"
    case inlineDollar = "Inline $…$"
    case inlineBracket = "Inline \\(…\\)"
    case displayDollar = "Display $$…$$"
    case displayBracket = "Display \\[…\\]"
    case equation = "Numbered equation"

    public func format(_ source: String) -> String {
        let body = source.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .bare: return body
        case .inlineDollar: return "$" + body + "$"
        case .inlineBracket: return "\\(" + body + "\\)"
        case .displayDollar: return "$$\n" + body + "\n$$"
        case .displayBracket: return "\\[\n" + body + "\n\\]"
        case .equation: return "\\begin{equation}\n" + body + "\n\\end{equation}"
        }
    }
}
