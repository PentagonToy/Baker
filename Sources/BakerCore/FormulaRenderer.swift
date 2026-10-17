import CoreGraphics
import CoreText
import Foundation

/// A deliberately bounded, native preview of common mathematics and simple matrices.
/// Unsupported TeX constructs throw, so callers can retain the literal source.
public enum FormulaRenderer {
    public static func render(_ latex: String, fontName: String = "STIXTwoMath-Regular", fontSize: CGFloat = 30, scale: CGFloat = 2) throws -> CGImage {
        guard latex.count <= 8000, latex.utf8.count <= 32_000 else { throw BakerError(message: "Formula preview is limited to 8,000 characters.") }
        guard fontSize.isFinite, (10...96).contains(fontSize), scale.isFinite, (0.5...3).contains(scale), !fontName.isEmpty, fontName.count <= 200 else {
            throw BakerError(message: "The formula preview font or scale is outside its supported range.")
        }
        var source = LatexWhitespace.compact(latex)
        for (open, close) in [("$$", "$$"), (#"\["#, #"\]"#), (#"\("#, #"\)"#), ("$", "$")] {
            if source.hasPrefix(open), source.hasSuffix(close), source.count >= open.count + close.count { source = String(source.dropFirst(open.count).dropLast(close.count)); break }
        }
        guard !source.isEmpty else { throw BakerError(message: "There is no formula to preview.") }
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        guard CTFontCopyPostScriptName(font) as String == fontName else { throw BakerError(message: "The requested formula preview font is unavailable.") }
        var parser = FormulaPreviewParser(source)
        let node = try parser.row(depth: 0)
        let box = try FormulaPreviewLayout(fontName: fontName).layout(node, size: fontSize)
        guard !box.paint.isEmpty else { throw BakerError(message: "There is no visible formula to preview.") }
        let padding: CGFloat = 16
        let width = ceil((box.width + padding * 2) * scale), height = ceil((box.ascent + box.descent + padding * 2) * scale)
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 8192, height <= 4096, width * height <= 16_000_000 else {
            throw BakerError(message: "Formula preview exceeds its 8192 × 4096 pixel or 16-megapixel limit.")
        }
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: Int(width) * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BakerError(message: "Could not allocate the formula preview.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: padding, y: padding + box.descent)
        context.setFillColor(CGColor(gray: 0.08, alpha: 1)); context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        context.setLineCap(.round); context.setLineJoin(.round)
        for operation in box.paint {
            switch operation {
            case let .text(line, transform):
                context.saveGState(); context.concatenate(transform); context.textMatrix = .identity; context.textPosition = .zero
                CTLineDraw(line, context); context.restoreGState()
            case let .stroke(points, thickness):
                guard let first = points.first else { continue }
                context.beginPath(); context.move(to: first)
                points.dropFirst().forEach { context.addLine(to: $0) }; context.setLineWidth(thickness); context.strokePath()
            }
        }
        guard let image = context.makeImage() else { throw BakerError(message: "Could not finish the formula preview.") }
        return image
    }
}

private indirect enum FormulaPreviewNode {
    case row([FormulaPreviewNode]), glyph(String, upright: Bool, large: Bool), space(CGFloat)
    case fraction(FormulaPreviewNode, FormulaPreviewNode, compact: Bool)
    case scripts(FormulaPreviewNode, upper: FormulaPreviewNode?, lower: FormulaPreviewNode?)
    case root(FormulaPreviewNode, index: FormulaPreviewNode?)
    case delimiters(String, FormulaPreviewNode, String)
    case sizedDelimiter(String, CGFloat)
    case style(String, FormulaPreviewNode)
    case matrix([[FormulaPreviewNode]], alignment: [Character], paired: Bool)
}

private struct FormulaPreviewParser {
    let input: [Character]
    var position = 0
    init(_ source: String) { input = Array(source) }
    mutating func whitespace() { while position < input.count && input[position].isWhitespace { position += 1 } }
    func starts(_ value: String) -> Bool {
        let token = Array(value), end = position + token.count
        return input[position...].starts(with: token) && (end == input.count || !(input[end].isASCII && input[end].isLetter))
    }
    func failure(_ message: String) -> BakerError { BakerError(message: message + " The literal LaTeX is still available.") }

    mutating func row(depth: Int, closing: Character? = nil, right: Bool = false, matrixCell: Bool = false) throws -> FormulaPreviewNode {
        guard depth <= 32 else { throw failure("Formula preview nesting exceeds 32 levels.") }
        var nodes: [FormulaPreviewNode] = []
        while true {
            whitespace()
            if position == input.count {
                guard closing == nil && !right else { throw failure("The formula has an unclosed group or delimiter.") }
                break
            }
            if let closing, input[position] == closing { position += 1; break }
            if right && starts(#"\right"#) { break }
            if matrixCell && (input[position] == "&" || input[position...].starts(with: ["\\", "\\"]) || starts(#"\end"#)) { break }
            guard input[position] != "}" else { throw failure("The formula has an unmatched closing brace.") }
            // TeX declarations apply to the remainder of their enclosing group.
            let declarations = ["bf": "mathbf", "rm": "mathrm", "it": "mathit", "sf": "mathsf", "tt": "mathtt", "cal": "mathcal"]
            if let name = declarations.keys.first(where: { starts("\\" + $0) }) {
                _ = command()
                nodes.append(.style(declarations[name]!, try row(depth: depth + 1, closing: closing, right: right, matrixCell: matrixCell)))
                return .row(nodes)
            }
            var node = try atom(depth: depth)
            var upper: FormulaPreviewNode?, lower: FormulaPreviewNode?
            while true {
                whitespace()
                guard position < input.count, input[position] == "^" || input[position] == "_" else { break }
                let mark = input[position]; position += 1
                if mark == "^" {
                    guard upper == nil else { throw failure("The formula repeats a superscript on the same base.") }
                    upper = try argument(depth: depth + 1)
                } else {
                    guard lower == nil else { throw failure("The formula repeats a subscript on the same base.") }
                    lower = try argument(depth: depth + 1)
                }
            }
            if upper != nil || lower != nil { node = .scripts(node, upper: upper, lower: lower) }
            nodes.append(node)
        }
        return .row(nodes)
    }

    mutating func argument(depth: Int) throws -> FormulaPreviewNode {
        guard depth <= 32 else { throw failure("Formula preview nesting exceeds 32 levels.") }
        whitespace()
        guard position < input.count, input[position] != "}" else { throw failure("A formula command is missing its argument.") }
        return try atom(depth: depth)
    }

    mutating func command() -> String {
        position += 1
        let start = position
        if position < input.count && input[position].isASCII && input[position].isLetter {
            while position < input.count && input[position].isASCII && input[position].isLetter { position += 1 }
        } else if position < input.count { position += 1 }
        return String(input[start..<position])
    }

    mutating func delimiter() throws -> String {
        whitespace()
        guard position < input.count else { throw failure("A scalable delimiter is missing.") }
        if input[position] == "\\" {
            let name = command()
            if let value = ["{": "{", "}": "}", "lbrace": "{", "rbrace": "}", "langle": "⟨", "rangle": "⟩", "lvert": "|", "rvert": "|", "vert": "|", "Vert": "‖", "lVert": "‖", "rVert": "‖" ][name] { return value }
        } else {
            let value = input[position]; position += 1
            if value == "." { return "" }
            if "()[]|".contains(value) { return String(value) }
        }
        throw failure("This scalable delimiter is not supported by formula preview.")
    }

    mutating func atom(depth: Int) throws -> FormulaPreviewNode {
        guard depth <= 32, position < input.count else { throw failure("The formula is incomplete or too deeply nested.") }
        let value = input[position]
        if value == "{" { position += 1; return try row(depth: depth + 1, closing: "}") }
        guard !"^_}&#%$".contains(value) else { throw failure("This formula contains an unmatched script or unsupported TeX syntax.") }
        if value != "\\" {
            position += 1
            if value == "~" { return .space(0.33) }
            return .glyph(value == "-" ? "−" : String(value), upright: !value.isLetter, large: false)
        }
        let name = command()
        let delimiterSizes: [String: CGFloat] = ["big": 1.2, "Big": 1.6, "bigg": 2.0, "Bigg": 2.4]
        let sizeName = ["l", "r", "m"].contains(String(name.suffix(1))) ? String(name.dropLast()) : name
        if let factor = delimiterSizes[sizeName] { return .sizedDelimiter(try delimiter(), factor) }
        if name == "begin" { return try matrix(depth: depth + 1) }
        if ["frac", "dfrac", "tfrac"].contains(name) {
            let numerator = try argument(depth: depth + 1), denominator = try argument(depth: depth + 1)
            return .fraction(numerator, denominator, compact: name == "tfrac")
        }
        if name == "sqrt" {
            whitespace(); var index: FormulaPreviewNode?
            if position < input.count && input[position] == "[" { position += 1; index = try row(depth: depth + 1, closing: "]") }
            return .root(try argument(depth: depth + 1), index: index)
        }
        if name == "left" {
            let left = try delimiter(), body = try row(depth: depth + 1, right: true)
            guard position < input.count, command() == "right" else { throw failure("A scalable delimiter has no matching right boundary.") }
            return .delimiters(left, body, try delimiter())
        }
        if ["mathrm", "mathit", "mathbf", "mathbb", "mathcal", "mathsf", "mathtt"].contains(name) { return .style(name, try argument(depth: depth + 1)) }
        if name == "text" || name == "operatorname" {
            whitespace(); guard position < input.count, input[position] == "{" else { throw failure("A text command needs a braced argument.") }
            position += 1; var text = ""
            while position < input.count && input[position] != "}" {
                guard !"{\\^_$%#&".contains(input[position]) && !input[position].isNewline else { throw failure("Nested TeX inside a text command is not supported by formula preview.") }
                text.append(input[position]); position += 1
            }
            guard position < input.count else { throw failure("A text command is unclosed.") }
            position += 1; return .glyph(text, upright: true, large: false)
        }
        if let width = [",": CGFloat(0.16), ";": 0.28, ":": 0.22, "!": -0.12, " ": 0.33, "quad": 1, "qquad": 2][name] { return .space(width) }
        if LatexWhitespace.standardOperators.contains(name) { return .glyph(LatexWhitespace.operatorText(name), upright: true, large: false) }
        if ["{", "}", "_", "%", "#", "&"].contains(name) { return .glyph(name, upright: true, large: false) }
        let leaves = Set(["alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "varpi", "rho", "varrho", "sigma", "varsigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega", "partial", "nabla", "infty", "int", "iint", "iiint", "oint", "sum", "prod", "pm", "mp", "times", "cdot", "div", "le", "leq", "ge", "geq", "ne", "neq", "approx", "equiv", "propto", "in", "notin", "subset", "subseteq", "supset", "supseteq", "cup", "cap", "to", "rightarrow", "leftarrow", "leftrightarrow", "rightleftharpoons", "leftrightharpoons", "Rightarrow", "Leftarrow", "Leftrightarrow", "forall", "exists", "neg", "land", "lor", "ell", "hbar", "Re", "Im", "langle", "rangle", "vert", "Vert", "ldots", "cdots"])
        guard leaves.contains(name) else { throw failure("Formula preview does not support command " + name + ".") }
        let converted = UnicodeMath.convert("\\" + name)
        guard converted.warnings.isEmpty, !converted.text.contains("\\") else { throw failure("Formula preview does not support command " + name + ".") }
        let greek = converted.text.unicodeScalars.allSatisfy { (0x391...0x3ff).contains($0.value) }
        return .glyph(converted.text, upright: !greek, large: ["int", "iint", "iiint", "oint", "sum", "prod"].contains(name))
    }

    mutating func literalGroup() throws -> String {
        whitespace(); guard position < input.count, input[position] == "{" else { throw failure("A matrix environment or column layout is missing.") }
        position += 1; let start = position
        while position < input.count && input[position] != "}" {
            guard input[position] != "{" && input[position] != "\\" else { throw failure("This matrix column layout is not supported.") }
            position += 1
        }
        guard position < input.count else { throw failure("A matrix environment name is unclosed.") }
        let text = String(input[start..<position]); position += 1; return text
    }

    mutating func matrix(depth: Int) throws -> FormulaPreviewNode {
        guard depth <= 32 else { throw failure("Formula preview nesting exceeds 32 levels.") }
        let name = try literalGroup()
        guard ["array", "matrix", "bmatrix", "pmatrix", "vmatrix", "Vmatrix", "Bmatrix", "aligned", "gathered", "cases"].contains(name) else {
            throw failure("Formula preview does not support environment " + name + ".")
        }
        var alignment: [Character] = []
        if name == "array" {
            alignment = Array(try literalGroup().filter { !$0.isWhitespace })
            guard !alignment.isEmpty, alignment.count <= 16, alignment.allSatisfy({ "lcr".contains($0) }) else { throw failure("Only simple l/c/r array columns are supported by formula preview.") }
        }
        whitespace()
        guard position == input.count || input[position] != "[" else { throw failure("Optional matrix positioning is not supported by formula preview.") }
        var rows: [[FormulaPreviewNode]] = [], cells: [FormulaPreviewNode] = []
        while position < input.count {
            whitespace()
            if starts(#"\end"#), cells.isEmpty, !rows.isEmpty { break }
            cells.append(try row(depth: depth, matrixCell: true))
            guard cells.count <= 16, rows.count < 32, rows.reduce(0, { $0 + $1.count }) + cells.count <= 256 else { throw failure("Matrices are limited to 32 rows, 16 columns and 256 cells.") }
            whitespace(); guard position < input.count else { throw failure("A matrix environment is unclosed.") }
            if input[position] == "&" { position += 1; continue }
            rows.append(cells); cells = []
            if starts(#"\end"#) { break }
            guard input[position...].starts(with: ["\\", "\\"]) else { throw failure("A matrix row separator is invalid.") }
            position += 2; whitespace()
            guard position == input.count || (input[position] != "[" && input[position] != "*") else { throw failure("Custom matrix row spacing is not supported by formula preview.") }
        }
        guard position < input.count, command() == "end", try literalGroup() == name else { throw failure("Matrix environment boundaries do not match.") }
        if name == "aligned" || name == "cases" {
            let maximum = rows.map(\.count).max() ?? 0
            let target = name == "cases" ? 2 : maximum + maximum % 2
            guard maximum <= target, target <= 16 else { throw failure("Too many alignment columns.") }
            rows = rows.map { $0 + Array(repeating: .row([]), count: target - $0.count) }
        }
        let columns = rows.first?.count ?? 0
        guard !rows.isEmpty, rows.count <= 32, columns > 0, rows.count * columns <= 256, rows.allSatisfy({ $0.count == columns }) else { throw failure("Matrix rows need a consistent number of columns.") }
        if alignment.isEmpty {
            if name == "aligned" { alignment = (0..<columns).map { $0.isMultiple(of: 2) ? "r" : "l" } }
            else if name == "cases" { alignment = ["l", "l"] }
            else { alignment = Array(repeating: "c", count: columns) }
        }
        guard alignment.count == columns, name != "gathered" || columns == 1 else { throw failure("The array columns do not match its cells.") }
        let body = FormulaPreviewNode.matrix(rows, alignment: alignment, paired: name == "aligned")
        if name == "cases" { return .delimiters("{", body, "") }
        if let pair = ["bmatrix": ["[", "]"], "pmatrix": ["(", ")"], "vmatrix": ["|", "|"], "Vmatrix": ["‖", "‖"], "Bmatrix": ["{", "}"]][name] { return .delimiters(pair[0], body, pair[1]) }
        return body
    }
}

private enum FormulaPreviewPaint {
    case text(CTLine, CGAffineTransform), stroke([CGPoint], CGFloat)
    func translated(x: CGFloat, y: CGFloat) -> FormulaPreviewPaint {
        switch self {
        case let .text(line, t): return .text(line, CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx + x, ty: t.ty + y))
        case let .stroke(points, thickness): return .stroke(points.map { CGPoint(x: $0.x + x, y: $0.y + y) }, thickness)
        }
    }
}
private struct FormulaPreviewBox {
    var width: CGFloat, ascent: CGFloat, descent: CGFloat
    var paint: [FormulaPreviewPaint]
    func shifted(x: CGFloat, y: CGFloat) -> [FormulaPreviewPaint] { paint.map { $0.translated(x: x, y: y) } }
}

private struct FormulaPreviewLayout {
    let fontName: String
    func glyph(_ text: String, size: CGFloat, upright: Bool = true, style: String? = nil) throws -> FormulaPreviewBox {
        var text = text
        if let style, style != "mathrm" {
            let result = UnicodeMath.convert("\\" + style + "{" + text + "}")
            guard result.warnings.isEmpty, !result.text.contains("\\") else { throw BakerError(message: "This mathematical alphabet is not supported by formula preview.") }
            text = result.text
        } else if !upright && style != "mathrm" { text = UnicodeMath.convert(text, italicVariables: true).text }
        if text.isEmpty { return FormulaPreviewBox(width: 0, ascent: 0, descent: 0, paint: []) }
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.08, alpha: 1)]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil)), bounds = CTLineGetImageBounds(line, nil)
        if bounds.isNull || bounds.isEmpty { return FormulaPreviewBox(width: advance, ascent: 0, descent: 0, paint: []) }
        let left = max(0, -bounds.minX)
        return FormulaPreviewBox(width: max(advance, bounds.maxX) + left, ascent: max(0, bounds.maxY), descent: max(0, -bounds.minY), paint: [.text(line, CGAffineTransform(translationX: left, y: 0))])
    }

    func layout(_ node: FormulaPreviewNode, size: CGFloat, style: String? = nil) throws -> FormulaPreviewBox {
        let box: FormulaPreviewBox
        switch node {
        case let .glyph(text, upright, large):
            var value = try glyph(text, size: size * (large ? 1.35 : 1), upright: upright, style: style)
            if ["+", "−", "=", "±", "∓", "×", "⋅", "÷", "≤", "≥", "≠", "≈", "∈", "→", "⇒"].contains(text) {
                let padding = size * 0.14; value.paint = value.shifted(x: padding, y: 0); value.width += padding * 2
            }
            if upright && LatexWhitespace.standardOperators.contains(text.replacingOccurrences(of: " ", with: "")) { value.width += size * 0.12 }
            box = value
        case let .sizedDelimiter(text, factor):
            var value = try glyph(text, size: size)
            let baseline = size * 0.25 * (1 - factor)
            value.paint = value.paint.map { operation in
                if case let .text(line, transform) = operation { return .text(line, CGAffineTransform(a: 1, b: 0, c: 0, d: factor, tx: transform.tx, ty: baseline)) }
                return operation
            }
            value.ascent = value.ascent * factor + baseline; value.descent = value.descent * factor - baseline
            box = value
        case let .space(width): box = FormulaPreviewBox(width: size * width, ascent: 0, descent: 0, paint: [])
        case let .style(name, body): box = try layout(body, size: size, style: name)
        case let .matrix(rows, alignment, paired):
            let cells = try rows.map { try $0.map { try layout($0, size: size * 0.95, style: style) } }
            let columns = alignment.count
            let widths = (0..<columns).map { column in cells.map { $0[column].width }.max() ?? 0 }
            let ascents = cells.map { max(size * 0.65, $0.map(\.ascent).max() ?? 0) }
            let descents = cells.map { max(size * 0.1, $0.map(\.descent).max() ?? 0) }
            let rowGap = size * 0.38
            let gaps = (0..<max(0, columns - 1)).map { paired ? size * ($0.isMultiple(of: 2) ? 0.12 : 1.5) : size * 0.65 }
            let height = zip(ascents, descents).reduce(CGFloat(0)) { $0 + $1.0 + $1.1 } + CGFloat(rows.count - 1) * rowGap
            let top = height / 2 + size * 0.25
            var paint: [FormulaPreviewPaint] = [], y = top
            for (index, row) in cells.enumerated() {
                let baseline = y - ascents[index]; var x: CGFloat = 0
                for (column, cell) in row.enumerated() {
                    let offset = alignment[column] == "l" ? 0 : alignment[column] == "r" ? widths[column] - cell.width : (widths[column] - cell.width) / 2
                    paint += cell.shifted(x: x + offset, y: baseline); x += widths[column] + (column < gaps.count ? gaps[column] : 0)
                }
                y = baseline - descents[index] - rowGap
            }
            box = FormulaPreviewBox(width: widths.reduce(0, +) + gaps.reduce(0, +), ascent: top, descent: max(0, height - top), paint: paint)
        case let .row(nodes):
            var width: CGFloat = 0, minX: CGFloat = 0, maxX: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0
            var paint: [FormulaPreviewPaint] = []
            for node in nodes {
                let child = try layout(node, size: size, style: style)
                if !child.paint.isEmpty { minX = min(minX, width); maxX = max(maxX, width + child.width) }
                paint += child.shifted(x: width, y: 0); width += child.width
                ascent = max(ascent, child.ascent); descent = max(descent, child.descent)
                guard width < 8192, paint.count <= 20_000 else { throw BakerError(message: "The formula is too wide or complex for a native preview.") }
            }
            box = FormulaPreviewBox(width: max(0, max(width, maxX) - minX), ascent: ascent, descent: descent, paint: paint.map { $0.translated(x: -minX, y: 0) })
        case let .fraction(numerator, denominator, compact):
            let childSize = max(5, size * (compact ? 0.7 : 0.9))
            let n = try layout(numerator, size: childSize, style: style), d = try layout(denominator, size: childSize, style: style)
            let pad = size * 0.16, gap = size * 0.13, thickness = max(0.7, size * 0.045), axis = size * 0.25
            let width = max(n.width, d.width) + pad * 2
            let ny = axis + gap + thickness / 2 + n.descent, dy = axis - gap - thickness / 2 - d.ascent
            let rule = FormulaPreviewPaint.stroke([CGPoint(x: 0, y: axis), CGPoint(x: width, y: axis)], thickness)
            box = FormulaPreviewBox(width: width + size * 0.12, ascent: ny + n.ascent, descent: max(0, -dy + d.descent), paint: n.shifted(x: (width - n.width) / 2, y: ny) + d.shifted(x: (width - d.width) / 2, y: dy) + [rule])
        case let .scripts(base, upper, lower):
            let b = try layout(base, size: size, style: style), scriptSize = max(5, size * 0.65)
            let u = try upper.map { try layout($0, size: scriptSize, style: style) }, l = try lower.map { try layout($0, size: scriptSize, style: style) }
            var uy = max(size * 0.5, b.ascent - size * 0.25), ly = -max(size * 0.28, b.descent + size * 0.08)
            if let u, let l { let missing = size * 0.15 - ((uy - u.descent) - (ly + l.ascent)); if missing > 0 { uy += missing / 2; ly -= missing / 2 } }
            let width = b.width + max(u?.width ?? 0, l?.width ?? 0) + size * 0.06
            box = FormulaPreviewBox(width: width, ascent: max(b.ascent, u.map { uy + $0.ascent } ?? 0), descent: max(b.descent, l.map { -ly + $0.descent } ?? 0), paint: b.paint + (u?.shifted(x: b.width, y: uy) ?? []) + (l?.shifted(x: b.width, y: ly) ?? []))
        case let .root(body, index):
            let b = try layout(body, size: size, style: style), degree = try index.map { try layout($0, size: max(5, size * 0.48), style: style) }
            let start = max(size * 0.6, (degree?.width ?? 0) * 0.8), top = b.ascent + size * 0.12, bottom = -b.descent - size * 0.03
            let width = start + b.width + size * 0.12, iy = top * 0.62
            let path = [CGPoint(x: start - size * 0.58, y: size * 0.2), CGPoint(x: start - size * 0.45, y: size * 0.28), CGPoint(x: start - size * 0.3, y: bottom), CGPoint(x: start - size * 0.1, y: top), CGPoint(x: width, y: top)]
            box = FormulaPreviewBox(width: width, ascent: max(top + 1, degree.map { iy + $0.ascent } ?? 0), descent: max(b.descent, -bottom + 1), paint: b.shifted(x: start, y: 0) + [.stroke(path, max(0.7, size * 0.04))] + (degree?.shifted(x: 0, y: iy) ?? []))
        case let .delimiters(left, body, right):
            let b = try layout(body, size: size, style: style)
            func stretched(_ text: String) throws -> FormulaPreviewBox {
                var value = try glyph(text, size: size)
                guard !value.paint.isEmpty else { return value }
                let stretch = max(1, (b.ascent + b.descent + size * 0.12) / max(1, value.ascent + value.descent))
                let baseline = (b.ascent - b.descent) / 2 - (value.ascent - value.descent) * stretch / 2
                value.paint = value.paint.map { operation in
                    if case let .text(line, transform) = operation { return .text(line, CGAffineTransform(a: 1, b: 0, c: 0, d: stretch, tx: transform.tx, ty: baseline)) }
                    return operation
                }
                value.ascent = value.ascent * stretch + baseline; value.descent = value.descent * stretch - baseline
                return value
            }
            let l = try stretched(left), r = try stretched(right), gap = size * 0.06
            box = FormulaPreviewBox(width: l.width + b.width + r.width + gap * 2, ascent: max(b.ascent, l.ascent, r.ascent), descent: max(b.descent, l.descent, r.descent), paint: l.paint + b.shifted(x: l.width + gap, y: 0) + r.shifted(x: l.width + gap + b.width + gap, y: 0))
        }
        guard box.width.isFinite, box.ascent.isFinite, box.descent.isFinite, box.width <= 8192, box.ascent + box.descent <= 4096 else {
            throw BakerError(message: "Formula preview dimensions exceed their safe limit.")
        }
        return box
    }
}
