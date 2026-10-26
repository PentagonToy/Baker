import CoreGraphics
import Foundation

/// Page-local geometry uses PDF coordinates (origin at the lower left).
public struct PDFRegion: Sendable {
    public enum Content: Sendable {
        case text(String), heading(String, level: Int), equation(String, label: String?), equationLabel(String)
        case figure(path: String, caption: String?), caption(String)
        case table([[String]])
    }
    public let id: Int
    public let bounds: CGRect
    public var content: Content
    public init(id: Int, bounds: CGRect, content: Content) {
        self.id = id; self.bounds = bounds; self.content = content
    }
}

/// Independent reconstruction rules; neither recognised mathematics nor source text is rewritten.
public enum PDFStructure {
    public static func reconstruct(_ regions: [PDFRegion]) -> [PDFRegion] {
        var result = regions
        var consumed = Set<Int>()
        // Associate by geometry before ordering: adjacent array items can belong to different columns.
        for index in result.indices {
            guard case .equationLabel(let label) = result[index].content else { continue }
            let box = result[index].bounds
            let candidates = result.indices.filter { candidate in
                guard case .equation(_, nil) = result[candidate].content else { return false }
                let equation = result[candidate].bounds
                return box.minX >= equation.maxX - 2 && box.minX - equation.maxX < max(80, equation.width * 0.5)
                    && abs(box.midY - equation.midY) <= max(box.height, equation.height) * 0.65
            }.sorted { abs(result[$0].bounds.midY - box.midY) < abs(result[$1].bounds.midY - box.midY) }
            guard let target = candidates.first else { continue }
            if candidates.count > 1,
               abs(abs(result[candidates[0]].bounds.midY - box.midY) - abs(result[candidates[1]].bounds.midY - box.midY)) < 2 { continue }
            if case .equation(let latex, _) = result[target].content {
                result[target].content = .equation(latex, label: label)
                consumed.insert(index)
            }
        }
        for index in result.indices {
            guard case .caption(let text) = result[index].content else { continue }
            let box = result[index].bounds
            let candidates = result.indices.filter { candidate in
                guard case .figure(_, nil) = result[candidate].content else { return false }
                let figure = result[candidate].bounds
                let overlap = max(0, min(box.maxX, figure.maxX) - max(box.minX, figure.minX))
                let gap = figure.minY - box.maxY
                return overlap >= min(box.width, figure.width) * 0.6 && gap >= -2 && gap <= max(24, box.height * 2)
            }.sorted { result[$0].bounds.minY - box.maxY < result[$1].bounds.minY - box.maxY }
            guard candidates.count == 1, let target = candidates.first else { continue }
            if case .figure(let path, _) = result[target].content {
                result[target].content = .figure(path: path, caption: text)
                consumed.insert(index)
            }
        }
        return readingOrder(result.enumerated().filter { !consumed.contains($0.offset) }.map(\.element))
    }

    /// Recursive whitespace cuts preserve columns; stable fallback preserves source order on ties.
    public static func readingOrder(_ regions: [PDFRegion]) -> [PDFRegion] {
        func order(_ items: [PDFRegion], depth: Int) -> [PDFRegion] {
            guard items.count > 1, depth < 32 else { return items }
            let heights = items.map { $0.bounds.height }.sorted()
            let typical = max(heights[heights.count / 2], 1)
            func gap(horizontal: Bool) -> (CGFloat, CGFloat)? {
                let intervals = items.map { horizontal ? ($0.bounds.minX, $0.bounds.maxX) : ($0.bounds.minY, $0.bounds.maxY) }.sorted { $0.0 < $1.0 }
                var end = intervals[0].1
                var best: (CGFloat, CGFloat)?
                for interval in intervals.dropFirst() {
                    let width = interval.0 - end
                    if horizontal ? width > (best?.1 ?? 0) : width >= typical * 0.75 { best = ((end + interval.0) / 2, width) }
                    end = max(end, interval.1)
                }
                return best
            }
            let x = gap(horizontal: true), y = gap(horizontal: false)
            if let x, x.1 >= typical * 1.2 {
                let left = items.filter { $0.bounds.maxX <= x.0 }
                let right = items.filter { $0.bounds.minX >= x.0 }
                if !left.isEmpty, !right.isEmpty, left.count + right.count == items.count {
                    return order(left, depth: depth + 1) + order(right, depth: depth + 1)
                }
            }
            if let y, y.1 >= typical * 0.75 {
                let top = items.filter { $0.bounds.minY >= y.0 }
                let bottom = items.filter { $0.bounds.maxY <= y.0 }
                if !top.isEmpty, !bottom.isEmpty, top.count + bottom.count == items.count {
                    return order(top, depth: depth + 1) + order(bottom, depth: depth + 1)
                }
            }
            return items.enumerated().sorted {
                if $0.element.bounds.maxY != $1.element.bounds.maxY { return $0.element.bounds.maxY > $1.element.bounds.maxY }
                if $0.element.bounds.minX != $1.element.bounds.minX { return $0.element.bounds.minX < $1.element.bounds.minX }
                return $0.offset < $1.offset
            }.map(\.element)
        }
        return order(regions, depth: 0)
    }

    public static func render(_ regions: [PDFRegion], format: PDFExportFormat) -> String {
        func text(_ value: String) -> String { format == .markdown ? PDFConverter.escapeMarkdown(value) : PDFConverter.escapeLaTeX(value) }
        return regions.map { region -> String in
            switch region.content {
            case .text(let value), .caption(let value), .equationLabel(let value): return text(value)
            case .heading(let value, let level):
                let level = min(max(level, 1), 6)
                if format == .markdown { return String(repeating: "#", count: level) + " " + text(value) }
                let command = level == 1 ? "section*" : level == 2 ? "subsection*" : "subsubsection*"
                return "\\\(command){\(text(value))}"
            case .equation(let latex, let label):
                // Labels are literal identifiers, not arbitrary TeX; ambiguous labels stay visible as prose.
                let valid = label.flatMap { $0.range(of: #"^[0-9]+(?:\.[0-9]+)*[a-zA-Z]?$"#, options: .regularExpression) != nil ? $0 : nil }
                let tagged = latex + (valid.map { " \\tag{\($0)}" } ?? "")
                let math = format == .markdown ? "$$\n\(tagged)\n$$" : "\\[\n\(tagged)\n\\]"
                return math + (label != nil && valid == nil ? "\n\n" + text(label!) : "")
            case .figure(let path, let caption):
                // Exporters receive owned relative assets, never an arbitrary URL or TeX command.
                let safe = !path.isEmpty && !path.hasPrefix("/") && !path.contains("..") && path.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil
                guard safe else { return text(caption ?? "Figure asset unavailable") }
                let image = format == .markdown ? "![](\(path))" : "\\begin{center}\\includegraphics[width=\\linewidth,keepaspectratio]{\(path)}\\end{center}"
                return image + (caption.map { "\n\n" + text($0) } ?? "")
            case .table(let rows):
                let width = rows.map(\.count).max() ?? 0
                guard width > 0 else { return "" }
                let cells = rows.map { row in (0..<width).map { text($0 < row.count ? row[$0] : "") } }
                if format == .markdown {
                    func row(_ values: [String]) -> String { "| " + values.joined(separator: " | ") + " |" }
                    return ([row(cells[0]), row(Array(repeating: "---", count: width))] + cells.dropFirst().map(row)).joined(separator: "\n")
                }
                return "\\begin{longtable}{" + String(repeating: "l", count: width) + "}\n" + cells.map { $0.joined(separator: " & ") + " \\\\" }.joined(separator: "\n") + "\n\\end{longtable}"
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n\n"
    }
}
