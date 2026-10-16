import Foundation

public struct MathConversion {
    public let text: String
    public let warnings: [String]
}

/// Internal representation of recognised formulae as editable Unicode maths.
/// No third-party replacement tables or conversion implementation are embedded.
public enum UnicodeMath {
    public static func convert(_ source: String, italicVariables: Bool = false) -> MathConversion {
        guard source.count <= 100_000 else {
            return MathConversion(text: source, warnings: ["Input exceeds 100,000 characters; conversion was skipped."])
        }
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), (#"\["#, #"\]"#), (#"\("#, #"\)"#), ("$", "$")] {
            if text.count >= open.count + close.count, text.hasPrefix(open), text.hasSuffix(close) {
                text = String(text.dropFirst(open.count).dropLast(close.count)); break
            }
        }
        var parser = MathParser(text, italicVariables: italicVariables)
        let output = parser.sequence(depth: 0, grouped: false)
        if parser.warnings.contains("Unclosed group; check the LaTeX source.") {
            return MathConversion(text: source, warnings: parser.warnings)
        }
        return MathConversion(text: output.precomposedStringWithCanonicalMapping, warnings: Array(Set(parser.warnings)).sorted())
    }
}

private struct MathParser {
    let characters: [Character]
    var position = 0
    var warnings: [String] = []
    var italicVariables: Bool
    var compactWhitespace = false
    init(_ source: String, italicVariables: Bool) {
        characters = Array(source); self.italicVariables = italicVariables
    }

    mutating func unstyledArgument(depth: Int, compact: Bool = true) -> String? {
        let previous = italicVariables
        italicVariables = false
        defer { italicVariables = previous }
        return argument(depth: depth, compact: compact)
    }

    mutating func sequence(depth: Int, grouped: Bool) -> String {
        guard depth < 64 else {
            warnings.append("Nesting limit reached; remaining source was preserved.")
            let rest = String(characters[position...]); position = characters.count; return rest
        }
        var output = ""
        while position < characters.count {
            if grouped && characters[position] == "}" { position += 1; return output }
            if characters[position] == "^" || characters[position] == "_" {
                output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            output += atom(depth: depth)
        }
        if grouped { warnings.append("Unclosed group; check the LaTeX source.") }
        return output
    }

    mutating func argument(depth: Int, compact: Bool? = nil) -> String? {
        let previous = compactWhitespace
        if let compact { compactWhitespace = compact }
        defer { compactWhitespace = previous }
        while position < characters.count && characters[position].isWhitespace { position += 1 }
        guard position < characters.count else { return nil }
        if characters[position] == "{" {
            position += 1
            return sequence(depth: depth + 1, grouped: true)
        }
        return atom(depth: depth + 1)
    }

    mutating func atom(depth: Int) -> String {
        guard position < characters.count else { return "" }
        guard depth < 64 else {
            warnings.append("Nesting limit reached; remaining source was preserved.")
            let rest = String(characters[position...]); position = characters.count; return rest
        }
        let start = position, character = characters[position]; position += 1
        if character == "{" { return sequence(depth: depth + 1, grouped: true) }
        if character == "^" || character == "_" {
            guard let body = unstyledArgument(depth: depth) else { return String(character) }
            let table = character == "^" ? Self.superscripts : Self.subscripts
            if body.allSatisfy({ table[$0] != nil }) { return body.map { table[$0]! }.joined() }
            warnings.append("Some scripts have no Unicode equivalent and were preserved.")
            return String(characters[start..<position])
        }
        guard character == "\\" else {
            if compactWhitespace && character.isWhitespace { return "" }
            return italicVariables ? Self.styled(character, command: "mathit") : String(character)
        }
        guard position < characters.count else { return "\\" }
        let commandStart = position
        if characters[position].isASCII && characters[position].isLetter {
            while position < characters.count && characters[position].isASCII && characters[position].isLetter { position += 1 }
        } else { position += 1 }
        let name = String(characters[commandStart..<position])
        if let symbol = Self.symbols[name] {
            // Named operators stay upright; only Greek variable symbols are styled.
            if italicVariables, symbol.unicodeScalars.count == 1,
               let value = symbol.unicodeScalars.first?.value, (0x391...0x3FF).contains(value),
               let character = symbol.first { return Self.styled(character, command: "mathit") }
            return symbol
        }
        if name == "left" || name == "right" {
            if position < characters.count && characters[position] == "." { position += 1 }
            return ""
        }
        if ["frac", "dfrac", "tfrac", "sfrac"].contains(name) {
            guard let numerator = argument(depth: depth, compact: true), let denominator = argument(depth: depth, compact: true) else {
                warnings.append("Incomplete fraction was preserved."); return String(characters[start..<position])
            }
            let simple = numerator + "/" + denominator
            if let fraction = Self.fractions[simple] { return fraction }
            return "(" + numerator + ")/(" + denominator + ")"
        }
        if name == "sqrt" {
            var index = ""
            while position < characters.count && characters[position].isWhitespace { position += 1 }
            if position < characters.count && characters[position] == "[" {
                position += 1
                while position < characters.count && characters[position] != "]" {
                    if !characters[position].isWhitespace { index.append(characters[position]) }
                    position += 1
                }
                guard position < characters.count else {
                    warnings.append("Incomplete root index was preserved."); return String(characters[start..<position])
                }
                position += 1
            }
            guard let body = argument(depth: depth, compact: true) else { return #"\sqrt"# }
            let prefix: String
            switch index { case "", "2": prefix = "√"; case "3": prefix = "∛"; case "4": prefix = "∜"
            default:
                if index.allSatisfy({ Self.superscripts[$0] != nil }) { prefix = index.map { Self.superscripts[$0]! }.joined() + "√" }
                else { warnings.append("Unsupported root index was preserved."); return String(characters[start..<position]) }
            }
            return prefix + "(" + body + ")"
        }
        if let accent = Self.accents[name] {
            guard let body = argument(depth: depth, compact: true), body.count == 1 else {
                warnings.append("Multi-character or incomplete accent was preserved.")
                return String(characters[start..<position])
            }
            return body + accent
        }
        if name == "not" {
            guard let body = argument(depth: depth, compact: true) else { return #"\not"# }
            if let negated = Self.negations[body] { return negated }
            if body.count == 1 { return body + "\u{0338}" }
            warnings.append("Unsupported negation was preserved."); return String(characters[start..<position])
        }
        if ["text", "mathrm", "operatorname", "mathit", "mathbf", "mathbb", "mathcal", "mathsf", "mathtt"].contains(name) {
            guard let body = unstyledArgument(depth: depth, compact: name != "text") else { return String(characters[start..<position]) }
            if ["text", "mathrm", "operatorname"].contains(name) { return body }
            return body.map { Self.styled($0, command: name) }.joined()
        }
        warnings.append("Unsupported command: \\" + name)
        if position < characters.count, characters[position] == "{" {
            position += 1
            return "\\" + name + "{" + sequence(depth: depth + 1, grouped: true) + "}"
        }
        return "\\" + name
    }

    private static func styled(_ character: Character, command: String) -> String {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return String(character) }
        let value = scalar.value
        if command == "mathit" {
            let variants: [UInt32: UInt32] = [0x3F4: 0x1D6F3, 0x3F5: 0x1D716, 0x3D1: 0x1D717,
                                             0x3F0: 0x1D718, 0x3D5: 0x1D719, 0x3F1: 0x1D71A, 0x3D6: 0x1D71B]
            var code = variants[value]
            if (0x391...0x3A9).contains(value), value != 0x3A2 { code = 0x1D6E2 + value - 0x391 }
            if (0x3B1...0x3C9).contains(value) { code = 0x1D6FC + value - 0x3B1 }
            if let code, let scalar = UnicodeScalar(code) { return String(scalar) }
        }
        let offsets: [String: (UInt32, UInt32, UInt32?)] = [
            "mathbf": (0x1D400, 0x1D41A, 0x1D7CE), "mathit": (0x1D434, 0x1D44E, nil),
            "mathbb": (0x1D538, 0x1D552, 0x1D7D8), "mathcal": (0x1D49C, 0x1D4B6, nil),
            "mathsf": (0x1D5A0, 0x1D5BA, 0x1D7E2), "mathtt": (0x1D670, 0x1D68A, 0x1D7F6)]
        let exceptions: [String: [Character: String]] = [
            "mathit": ["h": "ℎ"], "mathbb": ["C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ"],
            "mathcal": ["B": "ℬ", "E": "ℰ", "F": "ℱ", "H": "ℋ", "I": "ℐ", "L": "ℒ", "M": "ℳ", "R": "ℛ", "e": "ℯ", "g": "ℊ", "o": "ℴ"]]
        if let exception = exceptions[command]?[character] { return exception }
        guard let bases = offsets[command] else { return String(character) }
        var code: UInt32?
        if (65...90).contains(value) { code = bases.0 + value - 65 }
        else if (97...122).contains(value) { code = bases.1 + value - 97 }
        else if (48...57).contains(value), let digits = bases.2 { code = digits + value - 48 }
        return code.flatMap(UnicodeScalar.init).map(String.init) ?? String(character)
    }

    private static let superscripts = Dictionary(uniqueKeysWithValues: zip(Array("0123456789+-=()nix"), Array("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱˣ").map(String.init)))
    private static let subscripts = Dictionary(uniqueKeysWithValues: zip(Array("0123456789+-=()aehijklmnoprstuvx"), Array("₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ").map(String.init)))
    private static let accents = ["bar": "\u{0304}", "hat": "\u{0302}", "tilde": "\u{0303}", "dot": "\u{0307}", "ddot": "\u{0308}", "vec": "\u{20D7}", "underline": "\u{0332}", "overline": "\u{0305}"]
    private static let fractions = ["1/2": "½", "1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾", "1/5": "⅕", "2/5": "⅖", "3/5": "⅗", "4/5": "⅘", "1/6": "⅙", "5/6": "⅚", "1/8": "⅛", "3/8": "⅜", "5/8": "⅝", "7/8": "⅞"]
    private static let negations = ["∈": "∉", "∋": "∌", "=": "≠", "⊂": "⊄", "⊃": "⊅", "⊆": "⊈", "⊇": "⊉", "≤": "≰", "≥": "≱", "∃": "∄"]
    private static let symbols: [String: String] = {
        let names = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega".split(separator: " ").map(String.init)
        var values = Dictionary(uniqueKeysWithValues: zip(names, Array("αβγδεζηθικλμνξοπρστυφχψω").map(String.init)))
        for (name, symbol) in zip(names, Array("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ")) { values[name.prefix(1).uppercased() + name.dropFirst()] = String(symbol) }
        let extra = ["varepsilon": "ϵ", "vartheta": "ϑ", "varphi": "ϕ", "varrho": "ϱ", "varsigma": "ς", "varpi": "ϖ",
            "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "partial": "∂", "nabla": "∇", "infty": "∞",
            "times": "×", "cdot": "⋅", "pm": "±", "mp": "∓", "div": "÷", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠",
            "approx": "≈", "equiv": "≡", "sim": "∼", "simeq": "≃", "propto": "∝", "ll": "≪", "gg": "≫",
            "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "cup": "∪", "cap": "∩", "emptyset": "∅",
            "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "land": "∧", "lor": "∨", "perp": "⊥", "parallel": "∥",
            "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "mapsto": "↦",
            "ldots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "degree": "°",
            "langle": "⟨", "rangle": "⟩", "lvert": "|", "rvert": "|", "Vert": "‖", "{": "{", "}": "}", "%": "%", "_": "_", "$": "$", "#": "#", "&": "&",
            ",": "\u{2009}", ";": "\u{2005}", "!": "", " ": " ", "quad": "\u{2003}", "qquad": "\u{2003}\u{2003}",
            "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln", "exp": "exp", "lim": "lim", "max": "max", "min": "min", "det": "det"]
        values.merge(extra) { _, new in new }; return values
    }()
}
