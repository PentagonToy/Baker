import AppKit
import BakerCore

extension BakerAutomationServer {
    func handleScan(_ request: BakerAutomation.Request, _ model: Workbench) async throws -> [String: Any] {
        func fail(_ message: String) throws -> Never { throw FormulaAdapter.Failure(message: message) }
        if request.format == nil || request.format == "status" {
            return ["ok": true, "scan": model.scanSession?.diagnostic(limit: request.limit ?? 20, offset: request.offset ?? 0) ?? ["state": "idle"]]
        }
        if request.format == "start" {
            // Starting is idempotent: menu shortcuts alone may add a page or open review.
            if model.scanSession == nil {
                guard !model.busy, !model.shuttingDown else { try fail("Baker is busy.") }
                model.screenRecordingPermission.refresh()
                guard model.screenRecordingPermission.allowed else { try fail("Allow Screen Recording in Baker before starting a scan.") }
                model.startScan()
                guard model.scanSession != nil else { try fail("The scan could not start. Check Baker's current error.") }
            }
            return ["ok": true, "accepted": true, "scan": model.scanSession?.resourceState ?? ["state": "idle"]]
        }
        guard let session = model.scanSession else { try fail("Start a scan first.") }
        switch request.format {
        case "add":
            guard session.canAdd, !session.automatic else { try fail("Prepare a manual scan and finish the current page first.") }
            session.addPage()
        case "pause": session.pauseAuto()
        case "resume": if !session.automatic { try session.resumeAuto() }
        case "continue":
            guard session.phase == .review, !session.working else { try fail("Finish reviewing the current scan first.") }
            session.continueCapture()
        case "configure":
            guard let text = request.text else { try fail("Supply scan options as JSON with --text.") }
            try session.configure(ScanOptions.decode(text))
        case "review": session.review()
        case "close": await session.close()
        case "select", "retake", "remove", "move":
            guard session.phase == .review, !session.working, let text = request.text,
                  let id = UUID(uuidString: text), session.pages.contains(where: { $0.id == id }) else {
                try fail("Review the scan and supply a page UUID with --text.")
            }
            if request.format == "move", request.offset != -1 && request.offset != 1 { try fail("Move a page with --offset -1 or 1.") }
            session.selected = id
            if request.format == "retake" { session.continueCapture(retake: id) }
            if request.format == "remove" { session.removeSelected() }
            if request.format == "move" { session.moveSelected(request.offset!) }
        case "save":
            guard session.phase == .review, !session.working, !session.pages.isEmpty,
                  let path = request.output, path.hasPrefix("/"), !path.contains("\0"), path.lowercased().hasSuffix(".pdf") else {
                try fail("Review a scan and supply an absolute PDF --output path.")
            }
            session.savePDF(to: URL(fileURLWithPath: path))
        default: try fail("Choose status, start, configure, add, pause, resume, continue, review, select, retake, remove, move, save or close for scan --format.")
        }
        return ["ok": true, "accepted": true, "scan": model.scanSession?.resourceState ?? ["state": "idle"]]
    }
}
