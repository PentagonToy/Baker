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
        let warnings = Array(Set(parser.warnings)).sorted()
        if parser.preserveSource || parser.warnings.contains("Unclosed group; check the LaTeX source.") {
            return MathConversion(text: source, warnings: warnings)
        }
        return MathConversion(text: output.precomposedStringWithCanonicalMapping, warnings: warnings)
    }
}

private struct MathParser {
    let characters: [Character]
    var position = 0
    var warnings: [String] = []
    var italicVariables: Bool
    var compactWhitespace = false
    var fontCommand: String?
    var preserveSource = false
    var textMode = false
    init(_ source: String, italicVariables: Bool) {
        characters = Array(source); self.italicVariables = italicVariables
    }

    mutating func unstyledArgument(depth: Int, compact: Bool = true) -> String? {
        let previous = italicVariables, previousFont = fontCommand
        italicVariables = false; fontCommand = nil
        defer { italicVariables = previous; fontCommand = previousFont }
        return argument(depth: depth, compact: compact)
    }

    mutating func sequence(depth: Int, grouped: Bool) -> String {
        let previousFont = fontCommand
        defer { fontCommand = previousFont }
        guard depth < 64 else {
            warnings.append("Nesting limit reached; remaining source was preserved.")
            let rest = String(characters[position...]); position = characters.count; return rest
        }
        var output = ""
        while position < characters.count {
            if characters[position] == "}" {
                if grouped { position += 1; return output }
                preserveSource = true; warnings.append("Unexpected closing group; the LaTeX source was preserved.")
            }
            if characters[position] == "^" || characters[position] == "_" {
                output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let atomStart = position
            let value = atom(depth: depth)
            var next = position
            while next < characters.count && characters[next].isWhitespace { next += 1 }
            let hasScript = next < characters.count && (characters[next] == "^" || characters[next] == "_" || (!textMode && characters[next] == "'"))
            let raw = String(characters[atomStart..<position])
            let fraction = ["\\frac", "\\dfrac", "\\tfrac", "\\sfrac", "\\cfrac"].contains { raw.hasPrefix($0) }
            if hasScript, value.count > 1, characters[atomStart] == "{" || fraction {
                // Linear fractions and grouped sums need visible grouping before a script.
                output += "(" + value + ")"
            } else { output += value }
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
        if character == "'", !textMode {
            var count = 1
            while position < characters.count, characters[position] == "'" { position += 1; count += 1 }
            return [1: "′", 2: "″", 3: "‴", 4: "⁗"][count] ?? String(repeating: "′", count: count)
        }
        if character == "%" {
            while position < characters.count && !characters[position].isNewline { position += 1 }
            if position < characters.count { position += 1 }
            return ""
        }
        if character == "^" || character == "_" {
            guard let body = unstyledArgument(depth: depth) else {
                preserveSource = true; warnings.append("Missing script argument; the LaTeX source was preserved.")
                return String(character)
            }
            // Prime glyphs already occupy the superscript position; do not superscript them again.
            if character == "^", !body.isEmpty, body.allSatisfy({ "′″‴⁗‵‶‷".contains($0) }) {
                return ["′′": "″", "′′′": "‴", "′′′′": "⁗", "‵‵": "‶", "‵‵‵": "‷"][body] ?? body
            }
            let table = character == "^" ? Self.superscripts : Self.subscripts
            if body.allSatisfy({ table[$0] != nil }) { return body.map { table[$0]! }.joined() }
            warnings.append("This script is not supported by the Unicode converter; its LaTeX was preserved.")
            return String(characters[start..<position])
        }
        guard character == "\\" else {
            if compactWhitespace && character.isWhitespace { return "" }
            if let fontCommand { return Self.styled(character, command: fontCommand) }
            return italicVariables ? Self.styled(character, command: "mathit") : String(character)
        }
        guard position < characters.count else { return "\\" }
        let commandStart = position
        if characters[position].isASCII && characters[position].isLetter {
            while position < characters.count && characters[position].isASCII && characters[position].isLetter { position += 1 }
        } else { position += 1 }
        let name = String(characters[commandStart..<position])
        if ["ce", "ch", "chemfig"].contains(name) {
            warnings.append("Chemistry notation was preserved; Unicode conversion does not interpret \\" + name + ".")
            while position < characters.count, characters[position].isWhitespace { position += 1 }
            if position < characters.count, characters[position] == "{" {
                var level = 0
                repeat {
                    if characters[position] == "\\", position + 1 < characters.count { position += 2; continue }
                    if characters[position] == "{" { level += 1 }
                    if characters[position] == "}" { level -= 1 }
                    position += 1
                } while position < characters.count && level > 0
                if level != 0 { warnings.append("Unclosed group; check the LaTeX source.") }
            }
            return String(characters[start..<position])
        }
        if let declaration = ["bf": "mathbf", "it": "mathit", "rm": "mathrm", "sf": "mathsf", "tt": "mathtt", "cal": "mathcal"][name] {
            fontCommand = declaration
            while position < characters.count && characters[position].isWhitespace { position += 1 }
            return ""
        }
        if ["displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle", "limits", "nolimits", "tiny", "scriptsize", "footnotesize", "small", "normalsize", "large", "Large", "LARGE", "huge", "Huge"].contains(name) {
            warnings.append("Math layout directives are not represented in Unicode output.")
            return ""
        }
        if LatexWhitespace.standardOperators.contains(name) { return LatexWhitespace.operatorText(name) }
        if let symbol = Self.symbols[name] {
            if let fontCommand, symbol.count == 1, let character = symbol.first {
                if Self.isGreek(character), !["mathrm", "mathit", "mathbf"].contains(fontCommand) {
                    preserveSource = true; warnings.append("This Greek mathematical alphabet is not supported; the LaTeX source was preserved.")
                }
                return Self.styled(character, command: fontCommand)
            }
            // Named operators stay upright; only Greek variable symbols are styled.
            if italicVariables, symbol.unicodeScalars.count == 1,
               let value = symbol.unicodeScalars.first?.value, (0x391...0x3FF).contains(value),
               let character = symbol.first { return Self.styled(character, command: "mathit") }
            return symbol
        }
        if ["left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "bigm", "Bigl", "Bigr", "Bigm", "biggl", "biggr", "biggm", "Biggl", "Biggr", "Biggm"].contains(name) {
            if name != "left" && name != "right" {
                warnings.append("Delimiter sizing is not represented in Unicode output.")
            }
            while position < characters.count && characters[position].isWhitespace { position += 1 }
            guard validDelimiter(at: position) else {
                preserveSource = true; warnings.append("Invalid or missing delimiter; the LaTeX source was preserved.")
                return String(characters[start..<position])
            }
            if characters[position] == "." { position += 1 }
            return ""
        }
        if ["mathop", "mathord", "mathbin", "mathrel", "mathopen", "mathclose", "mathpunct", "mathinner"].contains(name) {
            guard let body = argument(depth: depth, compact: true) else {
                preserveSource = true; warnings.append("Missing mathematical argument; the LaTeX source was preserved.")
                return String(characters[start..<position])
            }
            return body
        }
        if ["frac", "dfrac", "tfrac", "sfrac", "cfrac"].contains(name) {
            if name == "cfrac" {
                while position < characters.count && characters[position].isWhitespace { position += 1 }
                if position < characters.count, characters[position] == "[" {
                    position += 1
                    let alignmentStart = position
                    while position < characters.count && characters[position] != "]" { position += 1 }
                    let alignment = String(characters[alignmentStart..<position]).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard position < characters.count, ["l", "r"].contains(alignment) else {
                        preserveSource = true; warnings.append("Unsupported fraction alignment; the LaTeX source was preserved.")
                        return String(characters[start..<position])
                    }
                    position += 1
                    warnings.append("Fraction alignment is not represented in Unicode output.")
                }
            }
            guard let numerator = argument(depth: depth, compact: true), let denominator = argument(depth: depth, compact: true) else {
                preserveSource = true; warnings.append("Incomplete fraction was preserved."); return String(characters[start..<position])
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
            guard let body = argument(depth: depth, compact: true) else {
                preserveSource = true; warnings.append("Incomplete root was preserved."); return #"\sqrt"#
            }
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
            guard let body = argument(depth: depth, compact: true) else { preserveSource = true; warnings.append("Incomplete negation was preserved."); return #"\not"# }
            if let negated = Self.negations[body] { return negated }
            if body.count == 1 { return body + "\u{0338}" }
            warnings.append("Unsupported negation was preserved."); return String(characters[start..<position])
        }
        if ["text", "textrm", "textnormal", "mbox", "hbox", "mathrm", "operatorname", "mathit", "mathbf", "mathbb", "mathcal", "mathsf", "mathtt", "mathfrak", "mathscr", "mathbfit", "boldsymbol"].contains(name) {
            if name == "operatorname" {
                while position < characters.count && characters[position].isWhitespace { position += 1 }
                if position < characters.count, characters[position] == "*" { position += 1 }
            }
            let textCommands = ["text", "textrm", "textnormal", "mbox", "hbox"]
            let previousTextMode = textMode
            textMode = textCommands.contains(name) || name == "operatorname"
            defer { textMode = previousTextMode }
            guard let body = unstyledArgument(depth: depth, compact: !textCommands.contains(name)) else { preserveSource = true; warnings.append("Missing text or style argument; the LaTeX source was preserved."); return String(characters[start..<position]) }
            if textCommands.contains(name) || ["mathrm", "operatorname"].contains(name) { return body }
            if !["mathit", "mathbf", "mathbfit", "boldsymbol"].contains(name), body.contains(where: Self.isGreek) {
                preserveSource = true; warnings.append("This Greek mathematical alphabet is not supported; the LaTeX source was preserved.")
            }
            return body.map { Self.styled($0, command: name) }.joined()
        }
        preserveSource = true
        warnings.append("Unsupported command; the LaTeX source was preserved: \\" + name)
        if position < characters.count, characters[position] == "{" {
            position += 1
            return "\\" + name + "{" + sequence(depth: depth + 1, grouped: true) + "}"
        }
        return "\\" + name
    }

    private func validDelimiter(at index: Int) -> Bool {
        guard index < characters.count else { return false }
        if "()[]|.<>/".contains(characters[index]) { return true }
        guard characters[index] == "\\", index + 1 < characters.count else { return false }
        var end = index + 1
        if characters[end].isASCII && characters[end].isLetter {
            while end < characters.count && characters[end].isASCII && characters[end].isLetter { end += 1 }
        } else { end += 1 }
        return ["{", "}", "|", "langle", "rangle", "lfloor", "rfloor", "lceil", "rceil", "vert", "lvert", "rvert", "Vert", "lVert", "rVert"].contains(String(characters[(index + 1)..<end]))
    }

    private static func isGreek(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value else { return false }
        return (0x391...0x3FF).contains(value)
    }

    private static func styled(_ character: Character, command: String) -> String {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return String(character) }
        let value = scalar.value
        let command = command == "mathscr" ? "mathcal" : command == "boldsymbol" ? "mathbfit" : command
        if let capitalBase: UInt32 = ["mathit": 0x1D6E2, "mathbf": 0x1D6A8, "mathbfit": 0x1D71C][command] {
            // Unicode's Greek blocks include capital theta symbol and final sigma.
            if (0x391...0x3A9).contains(value), value != 0x3A2 {
                return String(UnicodeScalar(capitalBase + value - 0x391)!)
            }
            if (0x3B1...0x3C9).contains(value) {
                return String(UnicodeScalar(capitalBase + 26 + value - 0x3B1)!)
            }
            let variants: [UInt32: UInt32] = [0x3F4: 17, 0x2207: 25, 0x2202: 51,
                0x3F5: 52, 0x3D1: 53, 0x3F0: 54, 0x3D5: 55, 0x3F1: 56, 0x3D6: 57]
            if let offset = variants[value] { return String(UnicodeScalar(capitalBase + offset)!) }
        }
        let offsets: [String: (UInt32, UInt32, UInt32?)] = [
            "mathfrak": (0x1D504, 0x1D51E, nil), "mathbfit": (0x1D468, 0x1D482, nil),
            "mathbf": (0x1D400, 0x1D41A, 0x1D7CE), "mathit": (0x1D434, 0x1D44E, nil),
            "mathbb": (0x1D538, 0x1D552, 0x1D7D8), "mathcal": (0x1D49C, 0x1D4B6, nil),
            "mathsf": (0x1D5A0, 0x1D5BA, 0x1D7E2), "mathtt": (0x1D670, 0x1D68A, 0x1D7F6)]
        let exceptions: [String: [Character: String]] = [
            "mathfrak": ["C": "ℭ", "H": "ℌ", "I": "ℑ", "R": "ℜ", "Z": "ℨ"],
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

    private static let superscripts = Dictionary(uniqueKeysWithValues: zip(Array("0123456789+-=()abcdefghijklmnoprstuvwxyzABDEGHIJKLMNOPRTUVW"), Array("⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂ").map(String.init)))
    private static let subscripts = Dictionary(uniqueKeysWithValues: zip(Array("0123456789+-=()aehijklmnoprstuvxβγρφχ"), Array("₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓᵦᵧᵨᵩᵪ").map(String.init)))
    private static let accents = ["check": "\u{030C}", "breve": "\u{0306}", "acute": "\u{0301}", "grave": "\u{0300}", "bar": "\u{0304}", "hat": "\u{0302}", "tilde": "\u{0303}", "dot": "\u{0307}", "ddot": "\u{0308}", "vec": "\u{20D7}", "underline": "\u{0332}", "overline": "\u{0305}"]
    private static let fractions = ["1/2": "½", "1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾", "1/5": "⅕", "2/5": "⅖", "3/5": "⅗", "4/5": "⅘", "1/6": "⅙", "5/6": "⅚", "1/8": "⅛", "3/8": "⅜", "5/8": "⅝", "7/8": "⅞"]
    private static let negations = ["∈": "∉", "∋": "∌", "=": "≠", "⊂": "⊄", "⊃": "⊅", "⊆": "⊈", "⊇": "⊉", "≤": "≰", "≥": "≱", "∃": "∄"]
    private static let symbols: [String: String] = {
        let names = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega".split(separator: " ").map(String.init)
        var values = Dictionary(uniqueKeysWithValues: zip(names, Array("αβγδεζηθικλμνξοπρστυφχψω").map(String.init)))
        for (name, symbol) in zip(names, Array("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ")) { values[name.prefix(1).uppercased() + name.dropFirst()] = String(symbol) }
        let extra = ["prime": "′", "dprime": "″", "trprime": "‴", "qprime": "⁗",
            "backprime": "‵", "backdprime": "‶", "backtrprime": "‷",
            "therefore": "∴", "because": "∵", "checkmark": "✓",
            "longrightarrow": "⟶", "longleftarrow": "⟵", "longleftrightarrow": "⟷",
            "Longrightarrow": "⟹", "Longleftarrow": "⟸", "Longleftrightarrow": "⟺", "longmapsto": "⟼",
            "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "vert": "|", "lVert": "‖", "rVert": "‖",
            "epsilon": "ϵ", "varepsilon": "ε", "vartheta": "ϑ", "phi": "ϕ", "varphi": "φ", "varrho": "ϱ", "varsigma": "ς", "varpi": "ϖ",
            "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "partial": "∂", "nabla": "∇", "infty": "∞",
            "times": "×", "cdot": "⋅", "pm": "±", "mp": "∓", "div": "÷", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠",
            "approx": "≈", "equiv": "≡", "sim": "∼", "simeq": "≃", "propto": "∝", "ll": "≪", "gg": "≫",
            "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "cup": "∪", "cap": "∩", "emptyset": "∅",
            "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "land": "∧", "lor": "∨", "perp": "⊥", "parallel": "∥",
            "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔", "rightleftharpoons": "⇌", "leftrightharpoons": "⇋", "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "mapsto": "↦",
            "ldots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "degree": "°",
            "langle": "⟨", "rangle": "⟩", "|": "‖", "mid": "∣", "lvert": "|", "rvert": "|", "Vert": "‖", "{": "{", "}": "}", "%": "%", "_": "_", "$": "$", "#": "#", "&": "&",
            ":": "\u{205F}", "thinspace": "\u{2009}", "medspace": "\u{205F}", "thickspace": "\u{2005}", "enspace": "\u{2002}",
            ",": "\u{2009}", ";": "\u{2005}", "!": "", " ": " ", "quad": "\u{2003}", "qquad": "\u{2003}\u{2003}",
            "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln", "exp": "exp", "lim": "lim", "max": "max", "min": "min", "det": "det"]
        values.merge(extra) { _, new in new }; return values
    }()
}
