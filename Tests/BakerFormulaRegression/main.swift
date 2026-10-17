import BakerCore
import CoreGraphics
import Foundation
import ImageIO

struct RegressionFailure: Error, CustomStringConvertible { let description: String }
var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw RegressionFailure(description: message) }
    checks += 1
}
func rejects(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { checks += 1; return }
    throw RegressionFailure(description: "Expected rejection: " + message)
}
func write(_ image: CGImage, _ url: URL) throws {
    guard let target = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw RegressionFailure(description: "PNG destination") }
    CGImageDestinationAddImage(target, image, nil)
    guard CGImageDestinationFinalize(target) else { throw RegressionFailure(description: "PNG encoding") }
}
func rowInk(_ image: CGImage) -> [Int] {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (0..<height).map { row in (0..<width).reduce(0) { total, column in total + (pixels[(row * width + column) * 4] < 128 ? 1 : 0) } }
}
func bands(_ rows: [Int]) -> [(start: Int, end: Int)] {
    var result: [(Int, Int)] = [], start: Int?
    for (index, value) in (rows + [0]).enumerated() {
        if value > 0 && start == nil { start = index }
        if value == 0, let first = start { result.append((first, index - 1)); start = nil }
    }
    return result
}
func run() throws {
    guard CommandLine.arguments.count == 2 else { throw RegressionFailure(description: "Pass a fresh external evidence directory.") }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: root.path) else { throw RegressionFailure(description: "Evidence directory already exists.") }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let integrity = root.appendingPathComponent("integrity.bin")
    try Data("abc".utf8).write(to: integrity)
    try ModelIntegrity.verify(integrity, bytes: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    try rejects("Model byte count") { try ModelIntegrity.verify(integrity, bytes: 4, sha256: "invalid") }
    try rejects("Model SHA-256") { try ModelIntegrity.verify(integrity, bytes: 3, sha256: String(repeating: "0", count: 64)) }
    let linked = root.appendingPathComponent("linked-model.bin")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: integrity)
    try rejects("Model symlinks") { try ModelIntegrity.verify(linked, bytes: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") }
    let burgers = #"\frac{\partial u}{\partial t}+u\frac{\partial u}{\partial x}=\nu\frac{\partial^2u}{\partial x^2}"#
    let actualBurgers = #"{\frac{\partial u}{\partial t}}+u\;{\frac{\partial u}{\partial x}}=\nu\;{\frac{\partial^{2}u}{\partial x^{2}}}"#
    let userArray = #"\mathbf{x}=\left[\begin{array}{l}0 \\ 1\end{array}\right]"#
    let keynoteMatrix = #"\mathbf{x}=\begin{bmatrix}0 \\ 1\end{bmatrix}"#
    let fixtures = ["burgers": burgers, "burgers-mfr": actualBurgers, "fraction": #"\frac{1}{2}"#, "scripts": #"x_i^2+y_{j+1}^{n-1}"#, "roots": #"\sqrt{x^2+1}+\sqrt[3]{\frac{a}{b}}"#, "integral": #"\int_0^1 x^2\,\mathrm{d}x=\frac{1}{3}"#, "delimiters": #"\left(\frac{a+b}{c}\right)^2=\left[\sqrt{x}\right]"#, "nested": #"\frac{1}{1+\frac{1}{x}}"#, "functions": #"\sin x+\cos^2\theta+\log\left(x\rightarrow y\right)"#, "text": #"\operatorname{Re}(z)+\text{speed}=\alpha+\nu"#, "array-user": userArray, "keynote-matrix": keynoteMatrix, "matrix-two-columns": #"A=\begin{pmatrix}a&b\\c&d\end{pmatrix}"#, "matrix-nested": #"\begin{bmatrix}\begin{pmatrix}a&b\\c&d\end{pmatrix}\\0\end{bmatrix}"#, "aligned": #"\begin{aligned}x&=a+b\\y&=c\end{aligned}"#]
    var summary: [String: Any] = [:]
    for (name, source) in fixtures {
        let image = try FormulaRenderer.render(source)
        try check(image.width > 64 && image.height > 64, "Visible fixture " + name)
        try check(rowInk(image).reduce(0, +) > 50, "Nonblank rendered ink " + name)
        try write(image, root.appendingPathComponent(name + ".png"))
        summary[name] = ["latex": source, "width": image.width, "height": image.height]
    }
    let legacyBold = try FormulaRenderer.render(#"\phi_{r}(x;{\bf p}_{r})"#)
    let modernBold = try FormulaRenderer.render(#"\phi_{r}(x;{\mathbf{p}}_{r})"#)
    try check(legacyBold.width == modernBold.width && legacyBold.height == modernBold.height, "Legacy bold declaration matches scoped modern notation")
    try check(try FormulaRenderer.render(#"{\bf p q}+r"#).width == FormulaRenderer.render(#"{\mathbf{p q}}+r"#).width, "Font declarations retain their enclosing group scope")
    let fraction = try FormulaRenderer.render(#"\frac{1}{2}"#)
    let rows = rowInk(fraction), ink = bands(rows)
    try check(ink.count == 3, "Fraction has separate numerator, rule and denominator ink bands")
    try check(ink[1].end - ink[1].start < ink[0].end - ink[0].start, "Fraction rule is thinner than numerator ink")
    try check(rows[ink[1].start...ink[1].end].max()! > rows[ink[0].start...ink[0].end].max()!, "Fraction rule spans more width than numeral")
    let plain = try FormulaRenderer.render("x2"), upper = try FormulaRenderer.render("x^2"), lower = try FormulaRenderer.render("x_2")
    try check(upper.height > plain.height + 5, "Superscript is placed above the baseline")
    try check(lower.height > plain.height + 5, "Subscript is placed below the baseline")
    try check(upper.width < plain.width, "Script uses a smaller glyph than a full-size baseline numeral")
    let display = try FormulaRenderer.render(#"\dfrac{a}{b}"#), compact = try FormulaRenderer.render(#"\tfrac{a}{b}"#)
    try check(display.height > compact.height, "Compact fraction has a smaller two-dimensional layout")
    let small = try FormulaRenderer.render(burgers, scale: 1), large = try FormulaRenderer.render(burgers, scale: 2)
    try check(abs(large.width - small.width * 2) <= 1 && abs(large.height - small.height * 2) <= 1, "Resolution scale preserves formula geometry")
    let grouped = try FormulaRenderer.render(actualBurgers)
    try check(grouped.height == large.height && grouped.width > large.width, "Actual MFR groups preserve stacked fractions and explicit spacing")
    try check(try FormulaRenderer.render(burgers, fontName: "STIXGeneral-Regular").width > 64, "Installed STIX alternative renders the equation")
    for source in ["", "   ", #"\unknown{x}"#, #"\begin{cases}a&b\end{cases}"#, #"\frac{1}"#, "{x", "x}", "^2", "x^2^3", #"\left(x"#, #"x\\y"#, #"\text{a\alpha}"#] {
        try rejects("Malformed or unsupported source: " + source) { _ = try FormulaRenderer.render(source) }
    }
    try rejects("Input length bound") { _ = try FormulaRenderer.render(String(repeating: "x", count: 8001)) }
    try rejects("Nesting bound") { _ = try FormulaRenderer.render(String(repeating: "{", count: 34) + "x" + String(repeating: "}", count: 34)) }
    try rejects("Canvas bound") { _ = try FormulaRenderer.render(String(repeating: "W", count: 1000)) }
    try rejects("Invalid font size") { _ = try FormulaRenderer.render("x", fontSize: .nan) }
    try rejects("Invalid scale") { _ = try FormulaRenderer.render("x", scale: 20) }
    try rejects("Unavailable font") { _ = try FormulaRenderer.render("x", fontName: "BakerMissingMathFont") }
    let serialisations: [(LatexCopyStyle, String)] = [(.bare, "x^2"), (.inlineDollar, "$x^2$"), (.inlineBracket, #"\(x^2\)"#), (.displayDollar, "$$\nx^2\n$$"), (.displayBracket, "\\[\nx^2\n\\]"), (.equation, "\\begin{equation}\nx^2\n\\end{equation}")]
    for (style, expected) in serialisations { try check(style.format("  x^2\n") == expected, "LaTeX copy wrapper: " + style.rawValue) }
    for (source, expected) in [
        (#"v _ { x } = v _ { x 0 }"#, #"v_{x}=v_{x0}"#),
        (#"\alpha x + \text{a b} \, y"#, #"\alpha x+\text{a b}\,y"#),
        (#"\operatorname*{arg max} x"#, #"\operatorname*{arg max}x"#)
    ] { try check(LatexWhitespace.compact(source) == expected, "Safe token whitespace: " + source) }
    let converted = KeynoteLatex.convert(userArray)
    try check(converted.text == keynoteMatrix && converted.warnings.isEmpty, "Exact Keynote array-to-bmatrix example preserves bold font")
    for (left, right, environment) in [("(", ")", "pmatrix"), ("[", "]", "bmatrix"), ("|", "|", "vmatrix"), (#"\Vert"#, #"\Vert"#, "Vmatrix"), (".", ".", "matrix")] {
        let source = "\\left" + left + #"\begin{array}{c}a\\b\end{array}\right"# + right
        try check(KeynoteLatex.convert(source).text == "\\begin{" + environment + #"}a\\b\end{"# + environment + "}", "Structurally matched matrix delimiter conversion: " + environment)
    }
    let nested = #"\left[\begin{array}{c}\left(\begin{array}{cc}a&b\\c&d\end{array}\right)\\0\end{array}\right]"#
    let nestedExpected = #"\begin{bmatrix}\begin{pmatrix}a&b\\c&d\end{pmatrix}\\0\end{bmatrix}"#
    try check(KeynoteLatex.convert(nested).text == nestedExpected, "Nested array and delimiter conversion")
    try check(KeynoteLatex.convert(#"\left[{{\begin{array}{c}0\\1\end{array}}}\right]"#).text == #"\begin{bmatrix}0\\1\end{bmatrix}"#, "Pure grouping braces around an array remain structural")
    try check(KeynoteLatex.convert(#"\begin{array}{cc}{a+b}&\frac{1}{2}\\c&d\end{array}"#).text == #"\begin{matrix}{a+b}&\frac{1}{2}\\c&d\end{matrix}"#, "Plain array conversion preserves nested braces and fractions")
    try check(KeynoteLatex.convert(#"\begin{array}{c}a\\b\\ \end{array}"#).text == #"\begin{matrix}a\\b\\ \end{matrix}"#, "A trailing row separator is retained")
    for source in [#"\left[\begin{array}{p{2cm}}a\\b\end{array}\right]"#, #"\begin{array}{|cc|}a&b\\c&d\end{array}"#, #"\begin{array}{c}a\\[4pt]b\end{array}"#, #"\begin{array}{c}\hline a\\b\end{array}"#, #"\begin{array}{cc}a&b\\c\end{array}"#, #"\begin{array}{c}a\end{matrix}"#] {
        let result = KeynoteLatex.convert(source)
        try check(result.text == source && !result.warnings.isEmpty, "Unsafe array layout preserved with warning: " + source)
    }
    for source in [burgers, #"\mathbf{x}+\mathbb{R}=\frac{1}{2}"#, #"\begin{bmatrix}a&b\\c&d\end{bmatrix}"#, #"\text{\begin{array}{c}literal\end{array}}"#] {
        try check(KeynoteLatex.convert(source).text == source, "Ordinary LaTeX and fonts preserved")
    }
    for source in [#"\begin{verbatim}\begin{array}{c}a\\b\end{array}\end{verbatim}"#, #"\newenvironment{custom}{\begin{array}{c}}{\end{array}}"#] {
        let result = KeynoteLatex.convert(source)
        try check(result.text == source && !result.warnings.isEmpty, "Literal environments and macro definitions remain untouched")
    }
    let vector = try FormulaRenderer.render(#"\begin{matrix}0\\1\end{matrix}"#)
    try check(bands(rowInk(vector)).count == 2, "Matrix raster has distinct vertically separated entry bands")
    let arrayImage = try FormulaRenderer.render(userArray), matrixImage = try FormulaRenderer.render(keynoteMatrix)
    try check(arrayImage.width == matrixImage.width && arrayImage.height == matrixImage.height, "Original array and converted matrix retain preview geometry")
    for source in [#"\begin{array}{p{2cm}}a\end{array}"#, #"\begin{matrix}a&b\\c\end{matrix}"#, #"\begin{bmatrix}a\\[4pt]b\end{bmatrix}"#, #"\begin{matrix}a\end{array}"#] {
        try rejects("Unsupported matrix preview: " + source) { _ = try FormulaRenderer.render(source) }
    }
    try rejects("Matrix row bound") { _ = try FormulaRenderer.render("\\begin{matrix}" + Array(repeating: "x", count: 33).joined(separator: "\\\\") + "\\end{matrix}") }
    try rejects("Matrix column bound") { _ = try FormulaRenderer.render("\\begin{matrix}" + Array(repeating: "x", count: 17).joined(separator: "&") + "\\end{matrix}") }
    let oversizedCells = "\\begin{matrix}" + Array(repeating: Array(repeating: "x", count: 16).joined(separator: "&"), count: 17).joined(separator: "\\\\") + "\\end{matrix}"
    try rejects("Matrix total-cell bound") { _ = try FormulaRenderer.render(oversizedCells) }
    // Output adapters must not adopt destructive KaTeX/regex cleanup from references.
    for source in [#"\mbox{velocity}"#, #"\hbox{a b}"#, #"\scalebox{2}{x}"#, #"\unknown{\alpha}"#, #"\text{literal \{a\}}"#] {
        try check(KeynoteLatex.convert(source).text == source, "Compatibility corpus preserves unsupported/literal source: " + source)
        try check(LatexCopyStyle.displayDollar.format(source) == "$$\n" + source + "\n$$", "Markdown wrapper preserves source: " + source)
    }
    summary["checks"] = checks
    try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("validation.json"))
    print("BakerFormulaRegression: \(checks) checks passed")
}

do { try run() } catch { fputs("BakerFormulaRegression failed: \(error)\n", stderr); exit(1) }
