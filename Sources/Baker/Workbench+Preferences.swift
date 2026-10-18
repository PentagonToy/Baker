import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

extension Workbench {
    var presetsDirectory: URL { storageDirectory.appendingPathComponent("Presets", isDirectory: true) }

    func chooseStorageFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Baker Save Folder"; panel.prompt = "Use Folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.directoryURL = storageDirectory
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.changeStorageDirectory(url) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func changeStorageDirectory(_ proposed: URL) async {
        guard !busy, !shuttingDown else { return }
        guard canChangeStorage?() != false else { report(BakerError(message: "Close the capture editor before changing the save folder.", code: .invalidState)); return }
        let directory = proposed.standardizedFileURL.resolvingSymlinksInPath()
        guard directory != storageDirectory else { return }
        guard directory.isFileURL else { report(BakerError(message: "Choose a folder on this Mac or in Finder.", code: .invalidInput)); return }
        switchingStorage = true; busy = true
        defer { switchingStorage = false; busy = false }
        await flushFormulaHistory()
        do {
            let store = CaptureStore(directory: directory)
            try await store.prepareLocation()
            let records = try await store.reconcileHistory(), formulas = try await store.savedFormulas()
            let recorded = try await store.recordings()
            guard !shuttingDown else { return }
            library.use(store); storageDirectory = directory
            preferences[PreferenceKeys.storageDirectory] = directory.path
            clipboardFlow.invalidate()
            formulaResults = [:]; savedFormulas = formulas; captures = records; recordings = recorded; historyRevision &+= 1
            focusedFormulaID = nil; activeCaptureID = nil; imageURL = nil; image = nil
            text = ""; latex = ""; unicode = ""; unicodeMessage = ""
            onStorageChanged?()
            status = "Save folder changed. Existing files remain in their previous folder."
        } catch { report(error, fallback: .storageFailed, context: "The save folder was not changed:") }
    }
    func settingsPreset() -> SettingsPreset {
        SettingsPreset(copyImages: copyCapturedImages, copyText: copyRecognisedText, openTextEditor: showResults,
            captureSounds: captureSounds, hideDesktopIcons: hideDesktopIcons, visibleCaptures: visibleCaptures,
            formulaHistoryLimit: formulaHistoryLimit, formulaHistoryDays: formulaHistoryDays, mathFont: mathFont,
            languages: selectedOCRLanguages, formulaFormat: preferredFormulaFormat.rawValue, latexStyle: preferredLatexStyle.rawValue)
    }
    func applySettingsPreset(_ preset: SettingsPreset) throws {
        try preset.validate()
        applyingPreset = true
        copyCapturedImages = preset.copyImages; copyRecognisedText = preset.copyText; showResults = preset.openTextEditor
        captureSounds = preset.captureSounds; hideDesktopIcons = preset.hideDesktopIcons; visibleCaptures = preset.visibleCaptures
        formulaHistoryLimit = preset.formulaHistoryLimit; formulaHistoryDays = preset.formulaHistoryDays; mathFont = preset.mathFont
        ocrLanguageSelection = preset.languages.joined(separator: ",")
        preferences[PreferenceKeys.formulaOutputFormat] = preset.formulaFormat
        preferences[PreferenceKeys.formulaLatexStyle] = preset.latexStyle
        applyingPreset = false
        applyFormulaRetention()
        status = "Preset loaded."
    }
    func saveSettingsPreset() {
        guard !busy else { return }
        let preset = settingsPreset(), directory = presetsDirectory
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { report(error, fallback: .storageFailed); return }
        let panel = NSSavePanel(); panel.title = "Save Baker Preset"; panel.directoryURL = directory
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Baker.json"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(preset).write(to: url, options: .atomic); self?.status = "Preset saved."
            } catch { self?.report(error, fallback: .storageFailed) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func loadSettingsPreset() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Load Baker Preset"; panel.directoryURL = presetsDirectory
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self, !self.busy else { return }
            self.busy = true
            Task {
                defer { self.busy = false }
                do {
                    let preset = try await Task.detached { try SettingsPreset.read(url) }.value
                    try self.applySettingsPreset(preset)
                } catch { self.report(error, fallback: .invalidInput, context: "Preset not loaded:") }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
