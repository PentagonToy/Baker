import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

extension Workbench {
    func adoptFormulas(_ values: [UUID: SavedFormula]) {
        if savedFormulas != values { historyRevision &+= 1 }
        savedFormulas = values
        formulaResults = formulaResults.filter { values[$0.key] != nil || $0.value.phase == .recognising }
        if let id = focusedFormulaID, values[id] == nil { focusedFormulaID = nil }
    }
    func applyFormulaRetention() {
        guard !shuttingDown, !switchingStorage, !applyingPreset else { return }
        let source = captureStore
        let pending = library.enqueue(.retain(limit: formulaHistoryLimit, days: formulaHistoryDays))
        Task {
            do {
                let values = try await pending.value
                if !shuttingDown, captureStore === source { adoptFormulas(values) }
            } catch { report(error, fallback: .storageFailed, context: "Formula retention could not be updated:") }
        }
    }
    func clearPreviewCache() {
        guard !busy else { return }
        FormulaPreviewRenderer.shared.clearCache()
        library.clearCache()
        formulaResults = [:]; focusedFormulaID = nil; image = nil
        status = "Cached previews cleared. Checking saved files…"
        refreshCaptureHistory()
    }
    func clearFormulaHistory() {
        guard !busy else { return }
        let source = captureStore, pending = library.enqueue(.clear)
        Task {
            do {
                _ = try await pending.value
                guard !shuttingDown, captureStore === source else { return }
                adoptFormulas([:]); latex = ""; unicode = ""; unicodeMessage = ""
                status = "Formula history cleared. Capture images remain."
            } catch { report(error, fallback: .storageFailed, context: "Formula history could not be cleared:") }
        }
    }
    func recognise(formula: Bool, outputFormat: OutputFormat = .latex) {
        guard !busy, !shuttingDown, let url = imageURL else { return }
        if formula, !developerRuntimeOverrides, !formulaSetup.ready {
            status = "Prepare formula recognition with one download in Settings → Formula."
            onFormulaSetupNeeded?(); return
        }
        let selectedPython = developerRuntimeOverrides ? python : formulaSetup.python
        let selectedConfig = developerRuntimeOverrides ? config : formulaSetup.configuration
        let captureID = activeCaptureID, languages = selectedOCRLanguages, finnish = finnishTextMode, tesseractPath = textEngineExecutable
        busy = true
        if formula, let captureID {
            if formulaResults[captureID] == nil, formulaResults.count >= 8,
               let oldest = captures.reversed().first(where: { formulaResults[$0.id] != nil }) {
               formulaResults.removeValue(forKey: oldest.id)
            }
           formulaResults[captureID] = FormulaResult(format: outputFormat, style: preferredLatexStyle)
            onFormulaReady?(captureID)
        }
        status = formula ? "Recognising formula…" : "Recognising text…"
        recognitionFlow.job = Task {
            defer { busy = false; recognitionFlow.job = nil }
            do {
                try Task.checkCancellation()
                guard !shuttingDown else { throw CancellationError() }
                let recognition = try await recognitionFlow.recognise(RecognitionRequest(url: url, formula: formula, python: selectedPython,
                    configuration: selectedConfig, languages: languages, finnish: finnish, tesseract: tesseractPath))
                let result = recognition.latex
                try Task.checkCancellation()
                guard !shuttingDown else { throw CancellationError() }
                if formula {
                    latex = result; format = outputFormat
                    let rendered = UnicodeMath.convert(result, italicVariables: true)
                    unicode = rendered.text
                    unicodeMessage = rendered.warnings.isEmpty
                        ? "Unicode approximates two-dimensional maths; LaTeX retains its structure."
                        : rendered.warnings.joined(separator: " ")
                    if let captureID {
                        let keynote = KeynoteLatex.convert(result)
                       formulaResults[captureID] = FormulaResult(phase: .ready, confidence: recognition.confidence, originalConfidence: recognition.confidence, originalLatex: result, model: recognition.model, confidenceMethod: recognition.confidenceMethod, diagnostics: recognition.diagnostics, latex: result, unicode: unicode,
                            keynote: LatexWhitespace.compact(keynote.text), keynoteWarning: keynote.warnings.joined(separator: " "), warning: unicodeMessage, format: outputFormat, style: preferredLatexStyle)
                        copyFormula(captureID)
                        do {
                            let preview = try await recognitionFlow.render(result)
                            if Task.isCancelled || shuttingDown { throw CancellationError() }
                           formulaResults[captureID]?.preview = preview
                        } catch is CancellationError { throw CancellationError() }
                        catch { formulaResults[captureID]?.previewError = BakerError.wrapping(error).userDescription }
                    } else { copyOutput() }
                } else {
                    // Invalidate any pending image copy before publishing the OCR result.
                    if copyRecognisedText {
                        try clipboardFlow.copyText(result)
                    }
                    text = result; format = .text
                    status = copyRecognisedText ? "Text copied." : "Recognition complete."
                }
                playCaptureFeedback(success: true)
                onResultReady?()
            } catch is CancellationError {
                status = "Recognition cancelled."
                if formula, let captureID {
                    if formulaResults[captureID]?.phase == .ready { formulaResults[captureID]?.previewError = "Preview cancelled. The recognised source remains available." }
                    else { formulaResults[captureID]?.phase = .failed; formulaResults[captureID]?.error = "Recognition cancelled. Try again when ready." }
                }
            } catch {
                status = "Recognition did not complete."
                if formula, let captureID {
                   formulaResults[captureID]?.phase = .failed
                   formulaResults[captureID]?.failure = BakerError.wrapping(error, fallback: .recognitionFailed)
                   formulaResults[captureID]?.error = BakerError.wrapping(error, fallback: .recognitionFailed).userDescription
                    if !shuttingDown { playCaptureFeedback(success: false) }
                } else if !shuttingDown { report(error, fallback: .recognitionFailed) }
            }
        }
    }
    func persistFormula(_ id: UUID) {
        guard !switchingStorage, let result = formulaResults[id], result.phase == .ready else { return }
        let value = SavedFormula(id: id, originalLatex: result.originalLatex.isEmpty ? result.latex : result.originalLatex,
            latex: result.latex, unicodeOverride: result.unicodeOverride, model: result.model,
            confidenceMethod: result.confidenceMethod, confidence: result.confidence, diagnostics: result.diagnostics,
            format: result.format.rawValue, style: result.style.rawValue, unicodeText: result.unicode, originalConfidence: result.originalConfidence ?? result.confidence, savedAt: savedFormulas[id]?.savedAt ?? Date())
        guard savedFormulas[id] != value else { return }
        let source = captureStore
        let pending = library.enqueue(.save(value, limit: formulaHistoryLimit, days: formulaHistoryDays))
        Task {
            do {
                let values = try await pending.value
                if !shuttingDown, captureStore === source { adoptFormulas(values) }
            } catch { report(error, fallback: .storageFailed, context: "Formula could not be saved:") }
        }
    }
    func recogniseSavedFormula(_ record: CaptureRecord) {
        guard !busy, !shuttingDown else { return }
        imageURL = captureURL(record); activeCaptureID = record.id
        recognise(formula: true, outputFormat: preferredFormulaFormat)
    }
    func openSavedFormula(_ id: UUID) {
        guard !busy, !shuttingDown, let value = savedFormulas[id] else { return }
        if formulaResults[id]?.phase != .ready {
            if formulaResults.count >= 8, let oldest = captures.reversed().first(where: { formulaResults[$0.id] != nil }) { formulaResults.removeValue(forKey: oldest.id) }
            let converted = UnicodeMath.convert(value.latex, italicVariables: true), keynote = KeynoteLatex.convert(value.latex)
           formulaResults[id] = FormulaResult(phase: .ready, confidence: value.confidence, originalConfidence: value.originalConfidence, wasEdited: value.originalLatex != value.latex,
                originalLatex: value.originalLatex, model: value.model, confidenceMethod: value.confidenceMethod,
                diagnostics: value.diagnostics, unicodeOverride: value.unicodeOverride, latex: value.latex,
                unicode: value.unicodeOverride ?? converted.text, keynote: LatexWhitespace.compact(keynote.text),
                keynoteWarning: keynote.warnings.joined(separator: " "), warning: converted.warnings.joined(separator: " "),
                format: OutputFormat(rawValue: value.format) ?? .latex, style: LatexCopyStyle(rawValue: value.style) ?? .bare)
            busy = true
            recognitionFlow.editJob = Task {
                defer { busy = false; recognitionFlow.editJob = nil }
                guard !shuttingDown, !Task.isCancelled else { return }
                do {
                    let rendered = try await recognitionFlow.render(value.latex)
                    guard !shuttingDown, !Task.isCancelled, formulaResults[id]?.latex == value.latex else { return }
                   formulaResults[id]?.preview = rendered
                } catch { formulaResults[id]?.previewError = BakerError.wrapping(error).userDescription }
            }
        }
        focusedFormulaID = id; onFormulaReady?(id)
    }
    func chooseFormulaFormat(_ id: UUID, _ selected: OutputFormat) {
        guard !switchingStorage, selected != .text, formulaResults[id]?.phase == .ready else { return }
        formulaResults[id]?.format = selected
        preferences[PreferenceKeys.formulaOutputFormat] = selected.rawValue
        if activeCaptureID == id { format = selected }
        copyFormula(id)
    }
    func chooseLatexStyle(_ id: UUID, _ style: LatexCopyStyle) {
        guard !switchingStorage, formulaResults[id]?.phase == .ready else { return }
        formulaResults[id]?.style = style
        preferences[PreferenceKeys.formulaLatexStyle] = style.rawValue
        copyFormula(id)
    }
    func editFormula(_ id: UUID) {
        guard !busy, !shuttingDown else { return }
        guard let result = formulaResults[id], result.phase == .ready else { return }
        activeCaptureID = id; latex = result.latex; unicode = result.unicode
        if let record = captures.first(where: { $0.id == id }) { imageURL = captureURL(record); image = NSImage(contentsOf: captureURL(record)) }
        format = result.format; unicodeMessage = result.warning
        onEditResult?()
    }
    func applyFormulaEdits() {
        guard !busy, let id = activeCaptureID, formulaResults[id]?.phase == .ready else { return }
        if format == .unicode {
           formulaResults[id]?.unicodeOverride = unicode
           formulaResults[id]?.unicode = unicode
           formulaResults[id]?.format = .unicode
            copyFormula(id)
            return
        }
        if formulaResults[id]?.latex != latex { formulaResults[id]?.confidence = nil; formulaResults[id]?.wasEdited = true }
        formulaResults[id]?.unicodeOverride = nil
        formulaResults[id]?.latex = latex
        let keynote = KeynoteLatex.convert(latex)
        formulaResults[id]?.keynote = LatexWhitespace.compact(keynote.text)
        formulaResults[id]?.keynoteWarning = keynote.warnings.joined(separator: " ")
        let converted = UnicodeMath.convert(latex, italicVariables: true)
        unicode = converted.text; unicodeMessage = converted.warnings.joined(separator: " ")
        formulaResults[id]?.unicode = unicode; formulaResults[id]?.warning = unicodeMessage
        formulaResults[id]?.format = format
        formulaResults[id]?.preview = nil; formulaResults[id]?.previewError = nil
        copyFormula(id)
        let source = latex
        busy = true
        recognitionFlow.editJob = Task {
            defer { busy = false; recognitionFlow.editJob = nil }
            guard !shuttingDown, !Task.isCancelled else { return }
            do {
                let preview = try await recognitionFlow.render(source)
                guard !Task.isCancelled, !shuttingDown else { throw CancellationError() }
               formulaResults[id]?.preview = preview
            } catch { if !shuttingDown { formulaResults[id]?.previewError = BakerError.wrapping(error).userDescription } }
        }
    }
    func copyFormula(_ id: UUID) {
        persistFormula(id)
        guard let result = formulaResults[id], result.phase == .ready else { return }
        do {
            if result.format == .unicode {
                try clipboardFlow.copyMath(result.unicode, font: selectedMathFont)
            } else {
                let text = result.format == .keynote ? result.keynote : result.format == .markdown ? LatexCopyStyle.displayDollar.format(result.latex) : result.style.format(result.latex)
                try clipboardFlow.copyText(text)
            }
            let message = "\(result.format.rawValue) copied"
           formulaResults[id]?.copiedFormat = result.format
           formulaResults[id]?.copyStatus = message
            status = message
        } catch {
           formulaResults[id]?.copiedFormat = nil
           formulaResults[id]?.copyStatus = "Copy failed — try again"
            status = BakerError.wrapping(error).userDescription
        }
    }
}
