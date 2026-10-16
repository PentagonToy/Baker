import Foundation

/// Converts only structurally understood array layouts; all other source is kept.
public enum KeynoteLatex {
    public static func convert(_ source: String) -> MathConversion {
        guard source.count <= 8000, source.utf8.count <= 32_000 else {
            return MathConversion(text: source, warnings: ["Keynote conversion is limited to 8,000 characters; the source was preserved."])
        }
        var converter = KeynoteArrayConverter(source)
        do {
            let text = try converter.rewrite(0..<converter.input.count, depth: 0)
            return MathConversion(text: text, warnings: Array(Set(converter.warnings)).sorted())
        } catch {
            return MathConversion(text: source, warnings: ["The array structure is incomplete or exceeds conversion limits; the source was preserved."])
        }
    }
}

private struct KeynoteArrayConverter {
    struct Environment { let name: String; let start: Int; let body: Range<Int>; let end: Int; let columns: String? }
    struct Delimited { let left: String; let right: String; let body: Range<Int>; let rightStart: Int; let end: Int }
    enum Invalid: Error { case structure }
    let input: [Character]
    var warnings: [String] = []
    init(_ source: String) { input = Array(source) }
    func text(_ range: Range<Int>) -> String { String(input[range]) }
    func skipSpace(_ index: Int, _ limit: Int) -> Int {
        var index = index; while index < limit && input[index].isWhitespace { index += 1 }; return index
    }
    func command(_ index: Int, _ limit: Int) -> (name: String, end: Int) {
        var end = index + 1
        if end < limit && input[end].isASCII && input[end].isLetter {
            while end < limit && input[end].isASCII && input[end].isLetter { end += 1 }
        } else if end < limit { end += 1 }
        return (text((index + 1)..<end), end)
    }
    func group(_ index: Int, _ limit: Int) throws -> (body: Range<Int>, end: Int) {
        let start = skipSpace(index, limit)
        guard start < limit, input[start] == "{" else { throw Invalid.structure }
        var index = start + 1, depth = 1
        while index < limit {
            if input[index] == "\\" { index = command(index, limit).end; continue }
            if input[index] == "{" { depth += 1; guard depth <= 32 else { throw Invalid.structure } }
            if input[index] == "}" { depth -= 1; if depth == 0 { return ((start + 1)..<index, index + 1) } }
            index += 1
        }
        throw Invalid.structure
    }
    func commentEnd(_ index: Int, _ limit: Int) -> Int {
        var index = index; while index < limit && !input[index].isNewline { index += 1 }; return index
    }
    func environment(_ start: Int, _ limit: Int) throws -> Environment {
        let opening = command(start, limit), nameGroup = try group(opening.end, limit), name = text(nameGroup.body)
        guard opening.name == "begin" else { throw Invalid.structure }
        var bodyStart = nameGroup.end, columns: String?
        if name == "array" { let preamble = try group(bodyStart, limit); columns = text(preamble.body); bodyStart = preamble.end }
        var stack = [name], index = bodyStart
        while index < limit {
            if input[index] == "%" { index = commentEnd(index, limit); continue }
            guard input[index] == "\\" else { index += 1; continue }
            let token = command(index, limit)
            if ["text", "operatorname", "mbox"].contains(token.name), skipSpace(token.end, limit) < limit, input[skipSpace(token.end, limit)] == "{" {
                index = try group(token.end, limit).end; continue
            }
            if token.name == "begin" || token.name == "end" {
                let tag = try group(token.end, limit), nested = text(tag.body)
                if token.name == "begin" { stack.append(nested); guard stack.count <= 32 else { throw Invalid.structure } }
                else {
                    guard stack.last == nested else { throw Invalid.structure }; stack.removeLast()
                    if stack.isEmpty { return Environment(name: name, start: start, body: bodyStart..<index, end: tag.end, columns: columns) }
                }
                index = tag.end
            } else { index = token.end }
        }
        throw Invalid.structure
    }
    func delimiter(_ start: Int, _ limit: Int) throws -> (value: String, end: Int) {
        let index = skipSpace(start, limit); guard index < limit else { throw Invalid.structure }
        if input[index] != "\\" { return (String(input[index]), index + 1) }
        let token = command(index, limit)
        return (["lvert": "|", "rvert": "|", "vert": "|", "lVert": "‖", "rVert": "‖", "Vert": "‖", "{": "{", "}": "}"][token.name] ?? "\\" + token.name, token.end)
    }
    func delimited(_ start: Int, _ limit: Int) throws -> Delimited {
        let left = try delimiter(command(start, limit).end, limit)
        var index = left.end, depth = 1
        while index < limit {
            if input[index] == "%" { index = commentEnd(index, limit); continue }
            guard input[index] == "\\" else { index += 1; continue }
            let token = command(index, limit)
            if token.name == "begin" { index = try environment(index, limit).end; continue }
            if ["text", "operatorname", "mbox"].contains(token.name), skipSpace(token.end, limit) < limit, input[skipSpace(token.end, limit)] == "{" { index = try group(token.end, limit).end; continue }
            if token.name == "left" { depth += 1; guard depth <= 32 else { throw Invalid.structure } }
            if token.name == "right" {
                depth -= 1
                if depth == 0 { let right = try delimiter(token.end, limit); return Delimited(left: left.value, right: right.value, body: left.end..<index, rightStart: index, end: right.end) }
            }
            index = token.end
        }
        throw Invalid.structure
    }
    mutating func eligible(_ environment: Environment) throws -> Bool {
        let columns = (environment.columns ?? "").filter { !$0.isWhitespace }
        guard !columns.isEmpty, columns.count <= 16, columns.allSatisfy({ "lcr".contains($0) }) else {
            warnings.append("An array has an unsupported column preamble; its original layout was preserved."); return false
        }
        var index = environment.body.lowerBound, cells = 1, rowCells: [Int] = [], lastWasRowSeparator = false
        while index < environment.body.upperBound {
            let value = input[index]
            if value == "%" { index = commentEnd(index, environment.body.upperBound); continue }
            if !value.isWhitespace { lastWasRowSeparator = false }
            if value == "{" { index = try group(index, environment.body.upperBound).end; continue }
            if value == "&" { cells += 1; index += 1; continue }
            if value == "\\" {
                let token = command(index, environment.body.upperBound)
                if token.name == "begin" { index = try self.environment(index, environment.body.upperBound).end; continue }
                if ["hline", "cline", "vline", "hdashline", "multicolumn", "multirow", "noalign", "omit", "extracolsep", "arraystretch", "tabularnewline", "cr"].contains(token.name) {
                    warnings.append("An array uses extra rules, spans or spacing; its original layout was preserved."); return false
                }
                if token.name == "\\" {
                    let next = skipSpace(token.end, environment.body.upperBound)
                    if next < environment.body.upperBound && (input[next] == "[" || input[next] == "*") { warnings.append("An array has custom row spacing; its original layout was preserved."); return false }
                    rowCells.append(cells); cells = 1
                    lastWasRowSeparator = true
                    if next == environment.body.upperBound { index = next; break }
                }
                index = token.end; continue
            }
            index += 1
        }
        if !lastWasRowSeparator || rowCells.isEmpty { rowCells.append(cells) }
        guard rowCells.count <= 32, rowCells.count * columns.count <= 256, rowCells.allSatisfy({ $0 == columns.count }) else {
            warnings.append("An array has irregular or excessive rows or columns; its original layout was preserved."); return false
        }
        if columns.count > 1 && columns.contains(where: { $0 != "c" }) { warnings.append("Keynote matrices use centred columns; explicit left/right array alignment was simplified.") }
        return true
    }
    mutating func matrix(_ environment: Environment, name: String, depth: Int) throws -> String {
        "\\begin{" + name + "}" + (try rewrite(environment.body, depth: depth + 1)) + "\\end{" + name + "}"
    }
    func soleArray(_ body: Range<Int>) throws -> Environment? {
        var range = body
        for _ in 0..<32 {
            let start = skipSpace(range.lowerBound, range.upperBound)
            var end = range.upperBound
            while end > start && input[end - 1].isWhitespace { end -= 1 }
            guard start < end else { return nil }
            if input[start] == "{" {
                let wrapped = try group(start, end)
                guard wrapped.end == end else { return nil }
                range = wrapped.body; continue
            }
            guard input[start] == "\\", command(start, end).name == "begin" else { return nil }
            let environment = try self.environment(start, end)
            return environment.name == "array" && environment.end == end ? environment : nil
        }
        throw Invalid.structure
    }
    mutating func rewrite(_ range: Range<Int>, depth: Int) throws -> String {
        guard depth <= 32 else { throw Invalid.structure }
        var index = range.lowerBound, output = ""
        while index < range.upperBound {
            if input[index] == "%" { let end = commentEnd(index, range.upperBound); output += text(index..<end); index = end; continue }
            guard input[index] == "\\" else { output.append(input[index]); index += 1; continue }
            let token = command(index, range.upperBound)
            if ["def", "gdef", "edef", "xdef", "newcommand", "renewcommand", "providecommand", "newenvironment", "renewenvironment", "DeclareMathOperator", "let", "futurelet", "verb", "catcode", "csname", "endcsname"].contains(token.name) { throw Invalid.structure }
            if ["text", "operatorname", "mbox"].contains(token.name), skipSpace(token.end, range.upperBound) < range.upperBound, input[skipSpace(token.end, range.upperBound)] == "{" {
                let end = try group(token.end, range.upperBound).end; output += text(index..<end); index = end; continue
            }
            if token.name == "left" {
                let delimited = try self.delimited(index, range.upperBound)
                if let array = try soleArray(delimited.body) {
                    let pairs = ["[,]": "bmatrix", "(,)": "pmatrix", "|,|": "vmatrix", "‖,‖": "Vmatrix", "{,}": "Bmatrix", ".,.": "matrix"]
                    if let name = pairs[delimited.left + "," + delimited.right], try eligible(array) {
                        output += try matrix(array, name: name, depth: depth); index = delimited.end; continue
                    }
                }
                output += text(index..<delimited.body.lowerBound) + (try rewrite(delimited.body, depth: depth + 1)) + text(delimited.rightStart..<delimited.end)
                index = delimited.end; continue
            }
            if token.name == "begin" {
                let environment = try self.environment(index, range.upperBound)
                if environment.name == "array" {
                    output += try eligible(environment) ? matrix(environment, name: "matrix", depth: depth) : text(index..<environment.end)
                } else if ["matrix", "bmatrix", "pmatrix", "vmatrix", "Vmatrix", "Bmatrix", "aligned", "gathered", "equation", "equation*", "align", "align*", "split", "gather", "gather*", "displaymath", "math"].contains(environment.name) {
                    output += text(index..<environment.body.lowerBound) + (try rewrite(environment.body, depth: depth + 1)) + text(environment.body.upperBound..<environment.end)
                } else {
                    warnings.append("An unsupported environment was preserved without rewriting its contents.")
                    output += text(index..<environment.end)
                }
                index = environment.end; continue
            }
            output += text(index..<token.end); index = token.end
        }
        return output
    }
}
