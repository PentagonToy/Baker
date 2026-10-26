import Foundation

MainActor.assumeIsolated {
    let domain = "Baker.QuickStartChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = BakerPreferences(defaults: defaults)
    var checks = 0
    func check(_ value: Bool) { precondition(value, "Check \(checks + 1)"); checks += 1 }
    let progress = QuickStartProgress(preferences: preferences)
    check(progress.step == .formula)
    progress.move(-1)
    check(progress.step == .formula)
    progress.step = .everyday; progress.move(1)
    check(progress.step == .everyday)
    progress.step = .scrolling
    check(QuickStartProgress(preferences: preferences).step == .scrolling)
    preferences[PreferenceKeys.quickStartStep] = 999
    check(QuickStartProgress(preferences: preferences).step == .formula)
    progress.step = .scrolling
    let id = UUID(), unrelated = UUID()
    progress.practising = true; progress.track(id)
    check(progress.practiceID == nil) // A closed guide cannot adopt a capture.
    progress.presented = true; progress.track(id)
    check(progress.practiceID == id)
    progress.observe([unrelated: FormulaResult(phase: .ready)])
    check(!progress.captured)
    progress.observe([id: FormulaResult(phase: .recognising)])
    check(!progress.captured && progress.practising)
    progress.observe([id: FormulaResult(phase: .failed)])
    check(!progress.captured && !progress.practising)
    progress.practising = true
    progress.observe([id: FormulaResult(phase: .ready)])
    check(progress.captured && !progress.practising && progress.step == .scrolling)
    progress.practising = true; progress.dismiss()
    check(!progress.presented && !progress.practising)
    check(preferences[PreferenceKeys.quickStartStep] == QuickStartProgress.Step.scrolling.rawValue)
    print("Quick Start: \(checks) checks passed")
}
