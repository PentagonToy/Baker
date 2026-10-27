import AppKit
import BakerCore

extension Workbench {
    func startScan() {
        if let scanSession { if scanSession.canAdd && !scanSession.automatic { scanSession.addPage() } else { scanSession.present() }; return }
        guard !busy, !shuttingDown else { return }
        screenRecordingPermission.refresh()
        guard screenRecordingPermission.allowed else {
            report(BakerError(message: "Allow Baker in Screen Recording before starting a scan.", code: .permissionDenied)); return
        }
        let directory = ScanSession.draftDirectory
        let exists = FileManager.default.fileExists(atPath: directory.appendingPathComponent("scan.json").path)
        do {
            let draft = try ScanDocument(directory: directory, resume: exists)
            busy = true; onCaptureVisibility?(false)
            let session = ScanSession(draft: draft, saveDirectory: storageDirectory, languages: selectedOCRLanguages, ended: { [weak self] in
                self?.scanSession = nil; self?.busy = false; self?.onCaptureVisibility?(true)
            }, saved: { [weak self] url in
                self?.exportURL = url; self?.exportProvider = "Baker · Local"; self?.exportSummary = "Scan saved as PDF."
                self?.status = "Scan saved to \(url.path)."
            })
            scanSession = session; session.start(resume: exists)
        } catch { report(error, fallback: .storageFailed) }
    }
}
