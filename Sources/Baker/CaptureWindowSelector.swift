import AppKit
import ScreenCaptureKit
import SwiftUI

/// Lists windows on demand without capturing a thumbnail for every application.
@MainActor
final class CaptureWindowSelector: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<SCWindow?, Never>?
    func choose(_ windows: [SCWindow]) async -> SCWindow? {
        guard !Task.isCancelled else { return nil }
        let ownWindows = Set(NSApp.windows.filter { $0.isVisible && $0.level == .normal }.map { UInt32($0.windowNumber) })
        let candidates = windows.filter {
            $0.windowLayer == 0 && $0.frame.width >= 2 && $0.frame.height >= 2 &&
            ($0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier || ownWindows.contains($0.windowID))
        }.sorted {
            let left = $0.owningApplication?.applicationName ?? ""
            let right = $1.owningApplication?.applicationName ?? ""
            return left == right ? $0.windowID < $1.windowID : left.localizedStandardCompare(right) == .orderedAscending
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Baker · Capture Window"
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: CaptureWindowList(windows: candidates, select: { [weak self] in self?.finish($0) }))
            self.panel = panel
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
    func cancel() { finish(nil) }
    func windowWillClose(_ notification: Notification) { finish(nil) }
    private func finish(_ window: SCWindow?) {
        let waiting = continuation
        continuation = nil
        panel?.orderOut(nil)
        panel?.delegate = nil
        panel = nil
        waiting?.resume(returning: window)
    }
}

private struct CaptureWindowList: View {
    let windows: [SCWindow]
    let select: (SCWindow?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a window").font(.headline)
            if windows.isEmpty {
                Text("No available windows. Open the window you want to capture and try again.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(windows, id: \.windowID) { window in
                            Button { select(window) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "macwindow").font(.title2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(window.owningApplication?.applicationName ?? "Application").font(.headline)
                                        Text(window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window").lineLimit(2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack { Spacer(); Button("Cancel") { select(nil) }.keyboardShortcut(.cancelAction) }
        }.padding(18).frame(width: 440, height: 400)
    }
}
