import Foundation
import SwiftUI
import BakerCore

/// Page-based progress, with startup excluded from the page-time estimate.
struct DocumentProgress {
    var total = 0
    var completed = 0
    var stage = "Preparing PDF…"
    let started: TimeInterval
    init(started: TimeInterval = ProcessInfo.processInfo.systemUptime) { self.started = started }
    private var pageStarted: TimeInterval?
    private var lastCompletion: TimeInterval?
    private var meanPageSeconds: Double?
    private var samples = 0
    var fraction: Double? { total > 0 ? min(0.99, Double(completed) / Double(total)) : nil }
    mutating func update(_ progress: PDFConversionProgress, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
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
    private static func colour(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : NSColor(red: red, green: green, blue: blue, alpha: 1)
        })
    }
    static let background = colour(0.975, 0.97, 0.955, dark: NSColor(red: 0.10, green: 0.13, blue: 0.14, alpha: 1))
    static let sidebar = colour(0.94, 0.935, 0.915, dark: NSColor(red: 0.085, green: 0.11, blue: 0.12, alpha: 1))
    static let surface = colour(0.995, 0.992, 0.98, dark: NSColor(red: 0.135, green: 0.165, blue: 0.175, alpha: 1))
    static let border = Color.primary.opacity(0.09)
    static let success = colour(0.25, 0.46, 0.36, dark: NSColor(red: 0.60, green: 0.77, blue: 0.66, alpha: 1))
    static let paper = colour(1, 1, 1, dark: .white)
    // Warm bread against the charcoal/slate palette of the authored Baker artwork.
    static let selectionForeground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 1) : .white
    })
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.88, green: 0.73, blue: 0.48, alpha: 1)
            : NSColor(red: 0.53, green: 0.35, blue: 0.15, alpha: 1)
    })
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
