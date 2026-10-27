import AppKit
import ScreenCaptureKit
import SwiftUI

/// Previews exist only while the picker is open; captures are serial and bounded in size.
@MainActor final class WindowPreviewQueue: ObservableObject {
    private var tail: Task<Void, Never>?
    func image(_ window: SCWindow) async throws -> CGImage {
        let previous = tail
        let work = Task { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            return try await Self.capture(window)
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    private static func capture(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let ratio = min(320 / max(window.frame.width, 1), 200 / max(window.frame.height, 1))
        config.width = max(2, Int(window.frame.width * ratio)); config.height = max(2, Int(window.frame.height * ratio))
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation(); return image
    }
}

@MainActor private final class WindowPickerState: ObservableObject {
    @Published var windows: [SCWindow] = []
    @Published var query = ""
    @Published var refreshing = false
    @Published var generation = 0
    var matches: [SCWindow] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return windows.filter { window in
            let name = (window.owningApplication?.applicationName ?? "") + " " + (window.title ?? "")
            return words.allSatisfy { name.localizedStandardContains(String($0)) }
        }
    }
}

@MainActor final class CaptureWindowSelector: NSObject, NSWindowDelegate {
    private var panel: NSWindow?
    private var continuation: CheckedContinuation<SCWindow?, Never>?
    private var refreshTask: Task<Void, Never>?
    private let state = WindowPickerState()
    private static func candidates(_ windows: [SCWindow]) -> [SCWindow] {
        let ownWindows = Set(NSApp.windows.filter { $0.isVisible && $0.level == .normal }.map { UInt32($0.windowNumber) })
        return windows.filter {
            $0.windowLayer == 0 && $0.frame.width >= 80 && $0.frame.height >= 60 && $0.owningApplication != nil &&
            ($0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier || ownWindows.contains($0.windowID))
        }
    }
    func choose(_ windows: [SCWindow]) async -> SCWindow? {
        guard !Task.isCancelled else { return nil }
        cancel(); state.windows = Self.candidates(windows); state.query = ""
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let value = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 510),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            value.title = "Baker · Choose Window"; value.minSize = NSSize(width: 560, height: 420)
            value.isReleasedWhenClosed = false; value.delegate = self
            value.contentView = NSHostingView(rootView: CaptureWindowGrid(state: state, reload: { [weak self] in self?.reload() }, select: { [weak self] in self?.finish($0) }))
            panel = value; value.center(); NSApp.activate(ignoringOtherApps: true); value.makeKeyAndOrderFront(nil)
        }
    }
    private func reload() {
        guard refreshTask == nil else { return }
        state.refreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { state.refreshing = false; refreshTask = nil }
            if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true), !Task.isCancelled {
                state.windows = Self.candidates(content.windows).filter { $0.windowID != UInt32(panel?.windowNumber ?? 0) }
                state.generation += 1
            }
        }
    }
    func cancel() { finish(nil) }
    func windowWillClose(_ notification: Notification) { finish(nil) }
    private func finish(_ window: SCWindow?) {
        let waiting = continuation; continuation = nil
        refreshTask?.cancel()
        panel?.delegate = nil; panel?.contentView = nil; panel?.close(); panel = nil
        state.windows = []; state.query = ""; waiting?.resume(returning: window)
    }
}

private struct CaptureWindowGrid: View {
    @ObservedObject var state: WindowPickerState
    let reload: () -> Void
    let select: (SCWindow?) -> Void
    @StateObject private var previews = WindowPreviewQueue()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Choose a window").font(BakerTypography.title)
                Spacer()
                TextField("Find a window", text: $state.query).textFieldStyle(.roundedBorder).frame(width: 190)
                Button(action: reload) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(BakerButtonStyle()).accessibilityLabel("Refresh windows").disabled(state.refreshing)
            }.padding(20)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 310), spacing: 16)], spacing: 18) {
                    ForEach(state.matches, id: \.windowID) { window in
                        CaptureWindowCard(window: window, previews: previews) { select(window) }
                    }
                }.padding(20).id(state.generation)
                if state.matches.isEmpty { Text("No matching windows").foregroundStyle(.secondary).padding(30) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(state.matches.count == 1 ? "1 window" : "\(state.matches.count) windows").font(BakerTypography.supporting).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { select(nil) }.buttonStyle(BakerButtonStyle()).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.background(BakerTheme.background).tint(BakerTheme.accent)
    }
}

@MainActor private final class WindowCardState: ObservableObject {
    @Published var image: NSImage?
    @Published var hovered = false
    @Published var failed = false
}
private struct CaptureWindowCard: View {
    let window: SCWindow
    let previews: WindowPreviewQueue
    let select: () -> Void
    @StateObject private var state = WindowCardState()
    @Environment(\.isFocused) private var focused
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(BakerTheme.surface)
                    if let image = state.image { Image(nsImage: image).resizable().scaledToFit().padding(6) }
                    else if state.failed { Image(systemName: "macwindow").font(.system(size: 28)).foregroundStyle(.secondary) }
                    else { ProgressView().controlSize(.small) }
                }.frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(state.hovered || focused ? BakerTheme.accent : BakerTheme.border, lineWidth: state.hovered || focused ? 2 : 1))
                HStack(spacing: 8) {
                    if let icon = window.owningApplication.flatMap({ NSRunningApplication(processIdentifier: $0.processID)?.icon }) {
                        Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.owningApplication?.applicationName ?? "Application").font(BakerTypography.section).lineLimit(1)
                        Text(window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window")
                            .font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { state.hovered = $0 }
            .accessibilityLabel((window.owningApplication?.applicationName ?? "Application") + ", " + (window.title ?? "Untitled window"))
            .task(id: window.windowID) {
                guard state.image == nil else { return }
                do {
                    let image = try await previews.image(window); try Task.checkCancellation()
                    state.image = NSImage(cgImage: image, size: .zero)
                } catch { if !Task.isCancelled { state.failed = true } }
            }.onDisappear { state.image = nil }
    }
}
