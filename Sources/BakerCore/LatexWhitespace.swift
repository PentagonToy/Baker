import Foundation

/// TeX ignores ordinary math whitespace. Keep text groups and command boundaries intact.
public enum LatexWhitespace {
    public static func compact(_ source: String) -> String {
        let input = Array(source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard input.count <= 100_000 else { return source }
        let textCommands: Set<String> = ["text", "textrm", "textnormal", "textbf", "textit", "mbox", "hbox", "operatorname"]
        func letter(_ c: Character) -> Bool { c.isASCII && c.isLetter }
        var output = "", i = 0, control = false, textGroup = false
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
                output += String(input[start..<i]); textGroup = false; control = false; continue
            }
            if textGroup, c == "*" { output.append(c); i += 1; control = false; continue }
            textGroup = false
            if c == "\\", i + 1 < input.count {
                output.append(c); i += 1
                if letter(input[i]) {
                    let start = i
                    while i < input.count, letter(input[i]) { output.append(input[i]); i += 1 }
                    control = true; textGroup = textCommands.contains(String(input[start..<i]))
                } else { output.append(input[i]); i += 1; control = false }
                continue
            }
            output.append(c); i += 1; control = false
        }
        return output
    }
}
