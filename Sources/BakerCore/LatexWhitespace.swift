import Foundation

/// TeX ignores ordinary math whitespace. Keep text groups and command boundaries intact.
public enum LatexWhitespace {
    public static let standardOperators: Set<String> = ["sin", "cos", "tan", "cot", "sec", "csc", "sinh", "cosh", "tanh", "coth", "arcsin", "arccos", "arctan", "log", "ln", "lg", "exp", "lim", "liminf", "limsup", "injlim", "projlim", "sup", "inf", "max", "min", "det", "gcd", "arg", "deg", "dim", "hom", "ker", "Pr"]
    public static func operatorText(_ name: String) -> String {
        ["liminf": "lim inf", "limsup": "lim sup", "injlim": "inj lim", "projlim": "proj lim"][name] ?? name
    }
    public static func compact(_ source: String) -> String {
        let input = Array(source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard input.count <= 100_000 else { return source }
        let textCommands: Set<String> = ["text", "textrm", "textnormal", "textbf", "textit", "mbox", "hbox", "operatorname", "ce", "ch", "chemfig"]
        func letter(_ c: Character) -> Bool { c.isASCII && c.isLetter }
        var output = "", i = 0, control = false, textGroup = false, operatorGroup = false
        while i < input.count {
            let c = input[i]
            if c == "%" { // Preserve TeX comments and their terminating newline.
                while i < input.count, input[i] != "\n" { output.append(input[i]); i += 1 }
                if i < input.count { output.append("\n"); i += 1 }; control = false; continue
            }
            if c.isWhitespace {
                while i < input.count, input[i].isWhitespace { i += 1 }
                if control, i < input.count, letter(input[i]) { output.append(" ") }
                continue
            }
            if textGroup, c == "{" {
                let start = i; var depth = 0
                repeat {
                    if input[i] == "\\", i + 1 < input.count { i += 2; continue }
                    if input[i] == "{" { depth += 1 }
                    if input[i] == "}" { depth -= 1 }
                    i += 1
                } while i < input.count && depth > 0
                guard depth == 0 else { return source }
                let body = String(input[(start + 1)..<(i - 1)])
                let name = body.filter { !$0.isWhitespace }
                if operatorGroup, output.hasSuffix("\\operatorname"), standardOperators.contains(name), body.allSatisfy({ $0.isWhitespace || ($0.isASCII && $0.isLetter) }) {
                    output = String(output.dropLast("\\operatorname".count)) + "\\" + name
                    if i < input.count, letter(input[i]) { output.append(" ") }
                    control = true
                } else { output += String(input[start..<i]); control = false }
                textGroup = false; operatorGroup = false; continue
            }
            if textGroup, c == "*" { output.append(c); i += 1; control = false; operatorGroup = false; continue }
            textGroup = false
            if c == "\\", i + 1 < input.count {
                output.append(c); i += 1
                if letter(input[i]) {
                    let start = i
                    while i < input.count, letter(input[i]) { output.append(input[i]); i += 1 }
                    control = true; textGroup = textCommands.contains(String(input[start..<i]))
                    operatorGroup = String(input[start..<i]) == "operatorname"
                } else { output.append(input[i]); i += 1; control = false }
                continue
            }
            output.append(c); i += 1; control = false
        }
        return output
    }
}
