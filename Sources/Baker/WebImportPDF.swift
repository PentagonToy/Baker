import AppKit
import CoreText

enum WebImportPDF {
    @MainActor
    static func stage(_ source: WebImportSource, in folder: URL) async throws -> URL {
        let document = try await WebImportRenderer().convert(source)
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let components = document.title.components(separatedBy: CharacterSet(charactersIn: "/:").union(.controlCharacters))
            let title = String(components.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            let name = title.isEmpty || title.hasPrefix(".") ? "Web Page" : title
            let input = folder.appendingPathComponent("input", isDirectory: true)
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
            let destination = input.appendingPathComponent(name).appendingPathExtension("pdf")
            let data = try make(document)
            try Task.checkCancellation()
            try data.write(to: destination, options: .atomic)
            return destination
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    static func make(_ document: WebImportDocument) throws -> Data {
        let data = NSMutableData()
        let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                      [kCGPDFContextTitle: document.title] as CFDictionary) else {
            throw WebImportError.pdfExport
        }
        let content = typeset(document)
        guard content.length > 0 else { throw WebImportError.empty }

        let framesetter = CTFramesetterCreateWithAttributedString(content)
        let area = CGPath(rect: page.insetBy(dx: 48, dy: 48), transform: nil)
        var offset = 0
        while offset < content.length {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), area, nil)
            let count = CTFrameGetVisibleStringRange(frame).length
            guard count > 0 else { throw WebImportError.pdfExport }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            offset += count
        }
        context.closePDF()
        return data as Data
    }

    private static func typeset(_ document: WebImportDocument) -> NSAttributedString {
        let content = NSMutableAttributedString()
        var literal = false
        var fence: String?
        var first = true
        for line in document.printText.split(separator: "\n", omittingEmptySubsequences: false) {
            if !literal, line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = String(line.prefix { $0 == line.first })
                if let open = fence {
                    if marker.hasPrefix(open), line.trimmingCharacters(in: .whitespaces) == marker { fence = nil; continue }
                } else { fence = marker; continue }
            }
            if line == "$$", fence == nil { literal.toggle(); continue }

            let heading = fence == nil && !literal ? line.prefix { $0 == "#" }.count : 0
            let isHeading = (1...6).contains(heading) && line.dropFirst(heading).first == " "
            let text = isHeading ? String(line.dropFirst(heading + 1)) : String(line)
            if first, !text.isEmpty {
                if !document.title.isEmpty, text != document.title {
                    append(document.title, to: content, font: .systemFont(ofSize: 20, weight: .semibold), spacing: 14)
                }
                first = false
            }
            let font: NSFont = isHeading ? .systemFont(ofSize: heading == 1 ? 20 : 14, weight: .semibold)
                : (literal || fence != nil ? .monospacedSystemFont(ofSize: 9, weight: .regular) : .systemFont(ofSize: 11))
            append(text, to: content, font: font, spacing: isHeading ? 6 : 2)
        }
        return content
    }

    private static func append(_ text: String, to content: NSMutableAttributedString, font: NSFont, spacing: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.lineBreakMode = .byWordWrapping
        content.append(NSAttributedString(string: text + "\n", attributes: [
            .font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph
        ]))
    }
}
