import AppKit
import BakerCore

extension Workbench {
    var approvedImagePolicy: CaptureRetentionPolicy {
        guard preferences[PreferenceKeys.imageHistoryApprovedDirectory] == storageDirectory.path else { return .init() }
        return .init(count: preferences[PreferenceKeys.imageHistoryLimit], days: preferences[PreferenceKeys.imageHistoryDays])
    }
    func adoptCaptureHistory(_ records: [CaptureRecord], formulas: [UUID: SavedFormula]) {
        let ids = Set(records.map(\.id))
        captures = records; savedFormulas = formulas
        formulaResults = formulaResults.filter { ids.contains($0.key) }
        if let id = focusedFormulaID, !ids.contains(id) { focusedFormulaID = nil; formulaInputPending = true }
        if let id = activeCaptureID, !ids.contains(id) {
            activeCaptureID = nil; imageURL = nil; image = nil; text = ""; latex = ""; unicode = ""; unicodeMessage = ""
        }
        historyRevision &+= 1
    }
    func refreshCaptureHistory(enforceLimits: Bool = false) {
        guard !busy, !shuttingDown, historyRefreshTask == nil else { return }
        historyNeedsMaintenance = false
        let source = captureStore, policy = approvedImagePolicy
        busy = true
        historyRefreshTask = Task {
            defer { historyRefreshTask = nil; busy = false }
            await library.flushHistory()
            var failure: Error?
            do {
                if enforceLimits, canChangeStorage?() != false {
                    let candidates = try await source.retentionCandidates(policy)
                    if !candidates.isEmpty { try await source.trashCaptures(candidates) }
                }
            } catch { failure = error }
            do {
                let records = try await source.reconcileHistory(), formulas = try await source.savedFormulas()
                let media = try await source.recordings()
                guard !shuttingDown, captureStore === source else { return }
                library.clearCache(); adoptCaptureHistory(records, formulas: formulas); recordings = media
                if let failure { report(failure, fallback: .storageFailed, context: "Some captures could not be moved to Trash:") }
            } catch { report(error, fallback: .storageFailed, context: "Capture history could not be refreshed:") }
        }
    }
    func clearImageCache() {
        guard !busy else { return }
        library.clearCache(); refreshCaptureHistory()
        status = "Image previews cleared. Checking saved files…"
    }
    func reviewImageRetention() {
        guard !busy, !shuttingDown else { return }
        guard canChangeStorage?() != false else { report(BakerError(message: "Close the capture editor before applying image limits.", code: .invalidState)); return }
        let source = captureStore, policy = CaptureRetentionPolicy(count: imageHistoryLimit, days: imageHistoryDays)
        busy = true
        historyRefreshTask = Task {
            defer { historyRefreshTask = nil; busy = false }
            await library.flushHistory()
            do {
                let candidates = try await source.retentionCandidates(policy)
                let records = try await source.records(), formulas = try await source.savedFormulas()
                guard !shuttingDown, captureStore === source else { return }
                library.clearCache(); adoptCaptureHistory(records, formulas: formulas)
                let bytes = candidates.reduce(Int64(0)) { $0 + Int64($1.bytes) }
                let linked = candidates.filter { formulas[$0.record.id] != nil }.count
                let alert = NSAlert()
                alert.messageText = candidates.isEmpty ? "Apply image history limits?" : "Move \(candidates.count) capture images to Trash?"
                alert.informativeText = candidates.isEmpty ? "No current images need removal. These limits will apply to future captures in this folder. Videos and GIFs are unaffected." : "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) will move to Trash. \(linked) linked formula results will be removed. These limits also apply to future captures in this folder. Videos and GIFs are unaffected."
                alert.addButton(withTitle: candidates.isEmpty ? "Apply Limits" : "Move to Trash & Apply")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn, !shuttingDown else { return }
                // Save the policy only after the reviewed removal succeeds.
                try await source.trashCaptures(candidates)
                preferences[PreferenceKeys.imageHistoryLimit] = policy.count
                preferences[PreferenceKeys.imageHistoryDays] = policy.days
                preferences[PreferenceKeys.imageHistoryApprovedDirectory] = storageDirectory.path
                let kept = try await source.records(), saved = try await source.savedFormulas()
                library.clearCache(); adoptCaptureHistory(kept, formulas: saved)
                status = "Image history limits applied."
            } catch {
                // A partial Trash operation must not leave stale cards or formula results in the UI.
                if let records = try? await source.reconcileHistory(), let formulas = try? await source.savedFormulas(), captureStore === source {
                    library.clearCache(); adoptCaptureHistory(records, formulas: formulas)
                }
                report(error, fallback: .storageFailed)
            }
        }
    }
}
