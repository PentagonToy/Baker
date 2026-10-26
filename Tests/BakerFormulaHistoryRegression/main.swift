import AppKit

var checks = 0
func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message); checks += 1
}
let source = #"x ^ {2} + 2 x + 1 = 0"#
expect(FormulaHistoryOutput.text(latex: source, unicode: nil, style: .bare, format: .latex) == "x^{2}+2x+1=0", "Compact LaTeX")
expect(FormulaHistoryOutput.text(latex: source, unicode: nil, style: .inlineDollar, format: .latex) == "$x^{2}+2x+1=0$", "Saved LaTeX style")
expect(FormulaHistoryOutput.text(latex: source, unicode: nil, style: .inlineDollar, format: .markdown) == "$$\nx^{2}+2x+1=0\n$$", "Markdown ignores saved LaTeX wrappers")
expect(FormulaHistoryOutput.text(latex: source, unicode: "custom unicode", style: .bare, format: .unicode) == "custom unicode", "Unicode edits preserved")
expect(FormulaHistoryOutput.text(latex: source, unicode: "", style: .bare, format: .unicode).isEmpty, "Explicit empty Unicode remains unavailable")
let unicode = FormulaHistoryOutput.text(latex: source, unicode: nil, style: .bare, format: .unicode)
expect(unicode.contains("²") && !unicode.contains("\\"), "Convert missing Unicode locally")
expect(FormulaHistoryOutput.text(latex: #"\unknownnotation{x}"#, unicode: nil, style: .bare, format: .unicode).isEmpty, "Unsupported Unicode cannot overwrite clipboard with TeX")
let matrix = #"\left[\begin{array}{cc}a&b\\c&d\end{array}\right]"#
let keynote = FormulaHistoryOutput.text(latex: matrix, unicode: nil, style: .equation, format: .keynote)
expect(keynote.contains("bmatrix") && !keynote.contains("array"), "Keynote destination conversion")
expect(FormulaHistoryOutput.text(latex: source, unicode: nil, style: .bare, format: .text).isEmpty, "Unsupported format rejected")
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
board.setString("sentinel", forType: .string)
_ = FormulaHistoryOutput.text(latex: source, unicode: nil, style: .bare, format: .markdown)
expect(board.string(forType: .string) == "sentinel", "Preparing output has no clipboard side effects")
print("\(checks) formula-history output checks passed")
