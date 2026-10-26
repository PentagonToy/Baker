import Foundation
import SwiftUI
import BakerCore

/// Page-based progress, with startup excluded from the page-time estimate.
struct DocumentProgress {
    var total = 0
    var completed = 0
    var stage = "Preparing PDF…"
    var provider: String?
    let started: TimeInterval
    init(started: TimeInterval = ProcessInfo.processInfo.systemUptime) { self.started = started }
    private var pageStarted: TimeInterval?
    private var lastCompletion: TimeInterval?
    private var meanPageSeconds: Double?
    private var samples = 0
    var fraction: Double? { total > 0 ? min(0.99, Double(completed) / Double(total)) : nil }
    mutating func update(_ progress: PDFConversionProgress, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let provider = progress.provider { self.provider = provider }
        guard progress.totalPages > 0, progress.completedPages >= completed else { return }
        total = progress.totalPages; stage = progress.message
        if progress.phase == .recognising || progress.phase == .reading, pageStarted == nil { pageStarted = now }
        if progress.completedPages > completed {
            let advanced = progress.completedPages - completed
            if let begin = lastCompletion ?? pageStarted {
                let seconds = max(0.01, (now - begin) / Double(advanced))
                meanPageSeconds = meanPageSeconds.map { 0.7 * $0 + 0.3 * seconds } ?? seconds
                samples += advanced
            }
            completed = progress.completedPages; lastCompletion = now
        }
    }
    func timing(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String {
        let elapsed = Self.duration(max(0, now - started))
        guard samples >= 2, let meanPageSeconds, let lastCompletion, completed < total else { return "Elapsed \(elapsed)" }
        let remaining = meanPageSeconds * Double(total - completed) - (now - lastCompletion)
        guard remaining > 0 else { return "Elapsed \(elapsed) · Taking longer than estimated" }
        return "Elapsed \(elapsed) · About \(Self.duration(remaining)) remaining"
    }
    private static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds.rounded(.up)))) sec" }
        return "\(Int((seconds / 60).rounded(.up))) min"
    }
}

@MainActor enum BakerTheme {
    private static func colour(_ light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let highContrast = [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                                .accessibilityHighContrastVibrantLight, .accessibilityHighContrastVibrantDark].contains(appearance.name)
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let darkAppearance = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = darkAppearance ? (highContrast ? highDark ?? dark : dark) : (highContrast ? highLight ?? light : light)
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    // Banner neutrals and wheat gold; surfaces and light-mode ink are contrast-adjusted derivatives.
    static let background = colour(0xECEEF1, dark: 0x1F2429)
    static let sidebar = colour(0xE2E6EB, dark: 0x1A1F24)
    static let surface = colour(0xF8F9FB, dark: 0x282F36)
    static let ink = colour(0x262C33, dark: 0xE8EBEE)
    static let border = colour(0xD1D7DF, dark: 0x414A55, highLight: 0x8F9BAA, highDark: 0x8C98A6)
    static let accent = colour(0x8B581F, dark: 0xEDBA68, highLight: 0x704315, highDark: 0xFFE9BE)
    static let success = accent
    static let paper = Color.white
    static let selectionForeground = colour(0xFFFFFF, dark: 0x1F2429)
}

struct DocumentProgressView: View {
    let progress: DocumentProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let fraction = progress.fraction {
                HStack {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BakerTheme.accent.opacity(0.15))
                            Capsule().fill(BakerTheme.accent).frame(width: geometry.size.width * fraction)
                        }
                    }.frame(height: 6).accessibilityValue(Text(fraction, format: .percent))
                    Text("\(Int(fraction * 100))% · \(progress.completed)/\(progress.total) pages").font(BakerTypography.supporting.monospacedDigit())
                }
            } else { ProgressView().controlSize(.small) }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(progress.timing()).font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
        }.accessibilityLabel("PDF conversion progress")
    }
}

/// A quiet, consistent indicator of the engine used for this result.
struct RecognitionProviderLabel: View {
    let provider: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: provider == "Saved result" ? "doc.text" : provider.hasPrefix("Plugin · ") ? "puzzlepiece.extension" : "desktopcomputer")
                .font(.system(size: 12, weight: .medium)).frame(width: 14, height: 14).accessibilityHidden(true)
            Text(provider)
        }
            .font(BakerTypography.supporting.weight(.semibold)).foregroundStyle(BakerTheme.success)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(BakerTheme.success.opacity(0.10), in: Capsule())
            .background(BakerTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BakerTheme.success.opacity(0.22)))
            .lineLimit(1).fixedSize().accessibilityElement(children: .combine)
    }
}
