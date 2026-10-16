import BakerCore
import AppKit
import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO

struct RegressionFailure: Error, CustomStringConvertible { let description: String }
var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw RegressionFailure(description: message) }
    checks += 1
}
func page(width: Int = 180, height: Int = 1600, repeated: Bool = false) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            let row = repeated ? y % 40 : y
            var hash = UInt64(row * width + x) &+ 0x9E3779B97F4A7C15
            hash = (hash ^ (hash >> 30)) &* 0xBF58476D1CE4E5B9
            hash = (hash ^ (hash >> 27)) &* 0x94D049BB133111EB
            hash ^= hash >> 31
            bytes[y * width + x] = UInt8(hash & 255)
        }
    }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: CGDataProvider(data: Data(bytes) as CFData)!,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
func crop(_ image: CGImage, _ y: Int, _ height: Int = 400) -> CGImage {
    image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))!
}
func rejected(_ outcome: StitchOutcome) -> Bool { if case .rejected = outcome { return true }; return false }
func writePNG(_ image: CGImage, _ url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw RegressionFailure(description: "PNG destination failed")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try check(CGImageDestinationFinalize(destination), "PNG encoding")
}

func run() throws {
    let inputFlags = fcntl(STDIN_FILENO, F_GETFD)
    for _ in 0..<2 {
        try check(try runProcess(URL(fileURLWithPath: "/usr/bin/true"), arguments: []).status == 0, "Repeated process invocation")
    }
    try check(fcntl(STDIN_FILENO, F_GETFD) == inputFlags, "Worker cleanup preserves application stdin")
    let input = Data("Baker worker input".utf8)
    try check(try runProcess(URL(fileURLWithPath: "/bin/cat"), arguments: [], input: input).output == input, "Owned worker input lifecycle")
    do {
        _ = try runProcess(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.05)
        throw RegressionFailure(description: "Process timeout must fail")
    } catch is BakerError { checks += 1 }
    let samples: [(String, String)] = [
        (#"\alpha + \beta = x^{12} + m_0"#, "α + β = x¹² + m₀"),
        (#"\mathbb{R} \infty \partial"#, "ℝ ∞ ∂"),
        (#"\frac{1}{2}"#, "½"), (#"\frac{a+b}{c}"#, "(a+b)/(c)"),
        (#"\sqrt{x^{2}+1}"#, "√(x²+1)"), (#"\sqrt[3]{x}"#, "∛(x)"),
        (#"\not\in"#, "∉"), (#"\dot{x}"#, "ẋ"), (#"\vec{v}"#, "v⃗"),
        (#"\mathbf{Az09}"#, "𝐀𝐳𝟎𝟗"), (#"\mathcal{H}"#, "ℋ"), (#"\mathit{h}"#, "ℎ"),
        (#"\alphabet"#, #"\alphabet"#), ("x_{qz}", "x_{qz}"),
        (#"\bar{xy}"#, #"\bar{xy}"#), (#"\frac{a}{b"#, #"\frac{a}{b"#),
        (#"\unknown{\alpha}"#, #"\unknown{α}"#),
        (#"{\frac{\partial u}{\partial t}}"#, "(∂u)/(∂t)"),
        (#"\{x\}"#, "{x}"), (#"$\alpha$"#, "α"),
        (#"\left(x\right)"#, "(x)"), (#"cm^{-1}"#, "cm⁻¹"),
        (#"\mathrm{Re}"#, "Re"), (#"\Gamma\rightarrow\Omega"#, "Γ→Ω")
    ]
    for (source, expected) in samples {
        let result = UnicodeMath.convert(source)
        try check(result.text == expected, "Unicode: \(source) expected \(expected), got \(result.text)")
    }
    try check(!UnicodeMath.convert(#"\unknown"#).warnings.isEmpty, "Unknown command coverage")
    try check(!UnicodeMath.convert(String(repeating: "^", count: 1000)).warnings.isEmpty, "Nesting bound")
    try check(!UnicodeMath.convert(String(repeating: "a", count: 100001)).warnings.isEmpty, "Input size bound")

    let styledSamples = [
        (#"x^{12} + \alpha x + \frac{1}{2}"#, "𝑥¹² + 𝛼 𝑥 + ½"),
        (#"\mathrm{Re} + \sin x + \text{speed}"#, "Re + sin 𝑥 + speed"),
        (#"\mathbf{x} + \mathbb{R} + h_0"#, "𝐱 + ℝ + ℎ₀"),
        (#"\Gamma + \Omega + \varsigma + \varphi"#, "𝛤 + 𝛺 + 𝜍 + 𝜙"),
        (#"\sqrt{x} + \vec{v}"#, "√(𝑥) + 𝑣⃗"),
        (#"x_{qz}"#, "𝑥_{qz}")
    ]
    for (source, expected) in styledSamples {
        let rendered = UnicodeMath.convert(source, italicVariables: true).text
        try check(rendered == expected, "Maths alphabet: \(source), expected \(expected), got \(rendered)")
    }
    try check(UnicodeMath.convert(#"x ^ { 1 2 } + \frac { 1 } { 3 }"#, italicVariables: true).text == "𝑥¹² + ⅓", "Actual model whitespace in scripts and fractions")
    try check(UnicodeMath.convert(#"\frac{\text{a b}}{c}"#, italicVariables: true).text == "(a b)/(𝑐)", "Text spaces survive compact mathematical arguments")
    try check(UnicodeMath.convert(#"\sqrt [ 3 ] { x }"#, italicVariables: true).text == "∛(𝑥)", "Model whitespace in root index")
    let formula = "𝑥² + 𝛼𝑥 + ½ = 0"
    for font in MathFont.allCases {
        let item = try MathClipboard.item(text: formula, font: font)
        try check(item.string(forType: .string) == formula, "Plain Unicode clipboard: \(font.rawValue)")
        let data = item.data(forType: .rtf)!
        let decoded = NSAttributedString(rtf: data, documentAttributes: nil)!
        try check(decoded.string == formula, "RTF preserves supplementary Unicode: \(font.rawValue)")
        let restoredFont = decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        try check(restoredFont?.fontName == font.resolvedFont.fontName, "RTF preserves selected/fallback font: \(font.rawValue)")
    }

    let source = page()
    var stitcher = ScrollStitcher()
    try check(try stitcher.append(crop(source, 0)) == .started, "Initial frame")
    try check(try stitcher.append(crop(source, 0)) == .unchanged, "Duplicate frame")
    let down = try stitcher.append(crop(source, 160))
    try check(down == .appended(160), "Downward 160px: \(down)")
    try check(try stitcher.append(crop(source, 320)) == .appended(160), "Second downward 160px")
    let stitched = try stitcher.render()
    try check(stitched.height == 720, "Stitched height")
    try check(try ScrollStitcher.isStable(crop(source, 0, 720), stitched), "Stitched pixel alignment")
    try check(try rejected(stitcher.append(crop(source, 160))), "Reverse movement")
    try check(try rejected(stitcher.append(crop(source, 1100))), "Missing overlap")
    try check(try rejected(stitcher.append(crop(source, 0, 450))), "Changed dimensions")
    try check(stitcher.height == 720, "Rejected frames preserve canvas")
    try check(try stitcher.append(crop(source, 480)) == .appended(160), "Recovery after rejection")
    var repeating = ScrollStitcher()
    let patterned = page(repeated: true)
    _ = try repeating.append(crop(patterned, 0))
    try check(try rejected(repeating.append(crop(patterned, 25))), "Ambiguous repeated pattern")
    var empty = ScrollStitcher()
    do { _ = try empty.render(); throw RegressionFailure(description: "Empty render must fail") } catch is BakerError { checks += 1 }
    do { _ = try empty.append(page(width: 40, height: 50)); throw RegressionFailure(description: "Tiny region must fail") } catch is BakerError { checks += 1 }

    if let path = ProcessInfo.processInfo.environment["BAKER_EVIDENCE_DIRECTORY"] {
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try MathClipboard.item(text: formula, font: .stixTwo).data(forType: .rtf)!
            .write(to: directory.appendingPathComponent("unicode-maths.rtf"))
        try formula.write(to: directory.appendingPathComponent("unicode-maths.txt"), atomically: true, encoding: .utf8)
        let fonts = MathFont.allCases.map { ["selected": $0.rawValue, "installed": $0.installedFont?.fontName ?? "unavailable", "resolved": $0.resolvedFont.fontName] }
        try JSONSerialization.data(withJSONObject: fonts, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("math-fonts.json"))
        try writePNG(stitched, directory.appendingPathComponent("stitched-regression.png"))
        let context = CGContext(data: nil, width: 1000, height: 500, bitsPerComponent: 8, bytesPerRow: 4000,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
        let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
        let lines = ["BAKER LOCAL OCR", "Capture a clue. Make it useful.", "Scrolling capture: 160 + 160 = 320", "Local processing. Ready to paste."]
        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)]
            context.textPosition = CGPoint(x: 48, y: 390 - index * 90)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes)), context)
        }
        let fixture = directory.appendingPathComponent("ocr-fixture.png")
        try writePNG(context.makeImage()!, fixture)
        let text = try recogniseText(fixture)
        try check(text.contains("BAKER LOCAL OCR"), "Real Vision OCR")
        try text.write(to: directory.appendingPathComponent("vision-result.txt"), atomically: true, encoding: .utf8)
    }
    print("PASS: \(checks) native regression checks")
}
do { try run() }
catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
