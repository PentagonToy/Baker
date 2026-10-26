import AppKit
import BakerCore
import SwiftUI

struct RecordingOptions {
    var format: RecordingFormat
    var showsCursor = true
    var capturesAudio = false
}

enum RecordingSetupResult {
    case start(RecordingOptions), reselect, cancel
}

/// Global desktop coordinates use a bottom-left origin; capture rectangles use top-left display coordinates.
enum RecordingPlacement {
    static func selection(_ rect: CGRect, on screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + rect.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
    static func controls(selection: CGRect, visible: CGRect, size: CGSize) -> CGRect {
        let below = selection.minY - size.height - 16
        let above = selection.maxY + 16
        let y = below >= visible.minY + 12 ? below : above + size.height <= visible.maxY - 12 ? above : visible.minY + 12
        return CGRect(x: min(max(selection.midX - size.width / 2, visible.minX + 12), max(visible.minX + 12, visible.maxX - size.width - 12)),
                      y: min(y, max(visible.minY + 12, visible.maxY - size.height - 12)), width: size.width, height: size.height)
    }
}

final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class RecordingSetup {
    private let preferences: BakerPreferences
    init(preferences: BakerPreferences = BakerPreferences()) { self.preferences = preferences }
    private var panel: RecordingPanel?
    private var outline: NSPanel?
    private var continuation: CheckedContinuation<RecordingSetupResult, Never>?

    func choose(region: CaptureRegion, preferredFormat: RecordingFormat?) async -> RecordingSetupResult {
        if Task.isCancelled { return .cancel }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let format = preferredFormat ?? RecordingFormat(rawValue: preferences[PreferenceKeys.recordingFormat]) ?? .video
                let rect = RecordingPlacement.selection(region.rect, on: region.screen.frame)
                outline = Self.outline(rect)
                let frame = RecordingPlacement.controls(selection: rect, visible: region.screen.visibleFrame, size: CGSize(width: 300, height: 246))
                let panel = RecordingPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                Self.style(panel)
                panel.onEscape = { [weak self] in self?.finish(.cancel) }
                panel.contentView = NSHostingView(rootView: RecordingSetupView(region: region, draft: RecordingSetupDraft(format: format)) { [weak self] result in self?.finish(result) })
                self.panel = panel
                panel.alphaValue = 0
                panel.makeKeyAndOrderFront(nil)
                Self.reveal(panel)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    func cancel() { finish(.cancel) }
    private func finish(_ result: RecordingSetupResult) {
        if case .start(let options) = result { preferences[PreferenceKeys.recordingFormat] = options.format.rawValue }
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        outline?.orderOut(nil); outline = nil
        let callback = continuation; continuation = nil
        callback?.resume(returning: result)
    }
    static func reveal(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 1
        }
    }
    static func style(_ panel: NSPanel) {
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.hasShadow = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    static func outline(_ selection: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: selection.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        style(panel); panel.ignoresMouseEvents = true; panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: [10, 5])).padding(1))
        panel.orderFrontRegardless()
        return panel
    }
}

@MainActor private final class RecordingSetupDraft: ObservableObject {
    @Published var format: RecordingFormat
    @Published var showsCursor = true
    @Published var capturesAudio = true
    init(format: RecordingFormat) { self.format = format }
}

private struct RecordingSetupView: View {
    let region: CaptureRegion
    @ObservedObject var draft: RecordingSetupDraft
    let complete: (RecordingSetupResult) -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Record", systemImage: "record.circle").font(.headline)
                Spacer()
                Button { complete(.cancel) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Cancel recording")
            }
            Picker("Format", selection: $draft.format) {
                Text("Video").tag(RecordingFormat.video)
                Text("GIF").tag(RecordingFormat.gif)
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text(dimensions).monospacedDigit().font(BakerTypography.supporting)
                Spacer()
                Button { complete(.reselect) } label: { Image(systemName: "viewfinder") }
                    .help("Choose another region").accessibilityLabel("Choose another region")
            }
            Toggle("Show cursor", isOn: $draft.showsCursor).toggleStyle(.checkbox).font(BakerTypography.body).frame(maxWidth: .infinity, alignment: .leading)
            if draft.format == .video {
                Toggle("System audio", isOn: $draft.capturesAudio).toggleStyle(.checkbox).font(BakerTypography.body).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("GIF has no sound", systemImage: "speaker.slash").font(BakerTypography.body).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { complete(.start(RecordingOptions(format: draft.format, showsCursor: draft.showsCursor, capturesAudio: draft.format == .video && draft.capturesAudio))) } label: {
                Label("Record \(draft.format.title)", systemImage: "record.circle.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            Text("\(draft.format.framesPerSecond) fps · Up to \(Int(draft.format.maximumDuration)) seconds")
                .font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.padding(16).frame(width: 300, height: 246).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
            .font(BakerTypography.body).tint(BakerTheme.accent)
    }
    private var dimensions: String {
        let size = try? draft.format.dimensions(width: Int(region.rect.width * region.screen.backingScaleFactor), height: Int(region.rect.height * region.screen.backingScaleFactor))
        return "\(size?.width ?? 0) × \(size?.height ?? 0) px"
    }
}
