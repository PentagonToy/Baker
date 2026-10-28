import SwiftUI
import AppKit

enum ScanSourceChoice: String, CaseIterable, Identifiable { case window = "Window", area = "Selected Area"; var id: String { rawValue } }
enum ScanAdvanceChoice: String, CaseIterable, Identifiable { case arrow = "Right Arrow", down = "Down Arrow", click = "Click a Button"; var id: String { rawValue } }

struct ScanDelayField: View {
    @Binding var seconds: Double
    var body: some View {
        HStack(spacing: 8) {
            TextField("Delay", value: $seconds, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 64)
                .accessibilityLabel("Page delay in seconds")
            Text("sec").foregroundStyle(.secondary)
        }.help("0.1–60 seconds after each page turn")
    }
}

struct ScanSetup: View {
    @ObservedObject var session: ScanSession
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scan pages").font(BakerTypography.title)
                Spacer()
                Image(systemName: "doc.viewfinder").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
            HStack(alignment: .top, spacing: 24) {
                source.frame(width: 300)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Capture").font(BakerTypography.section)
                        BakerSegmentedPicker(title: "Capture region", selection: $session.sourceChoice,
                            choices: [("Window", .window), ("Area", .area)]).frame(height: 32)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Next page").font(BakerTypography.section)
                        BakerSegmentedPicker(title: "Next-page action", selection: $session.advanceChoice,
                            choices: [("→", .arrow), ("↓", .down), ("Click", .click)]).frame(height: 32)
                            .help("Use Right Arrow, Down Arrow or a next-page button chosen on the window preview.")
                    }
                    HStack {
                        Text("Delay").font(BakerTypography.section)
                        Spacer(minLength: 8)
                        ScanDelayField(seconds: $session.turnDelay)
                    }
                }.frame(width: 248).disabled(session.sourceName == nil)
            }.padding(.horizontal, 24).padding(.bottom, 22)
            if !session.accessibilityAllowed {
                HStack {
                    Label("Control access needed", systemImage: "lock").font(BakerTypography.supporting).foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow…", action: session.openAccessibilitySettings).buttonStyle(BakerButtonStyle())
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            Divider()
            HStack {
                Button("Manual") { session.beginConfiguredScan(automatic: false) }
                    .buttonStyle(BakerButtonStyle()).disabled(session.sourceName == nil)
                Spacer()
                Button("Start Scan") { session.beginConfiguredScan(automatic: true) }
                    .buttonStyle(BakerButtonStyle(prominent: true)).disabled(!session.accessibilityAllowed || session.sourceName == nil)
                    .keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 620).fixedSize(horizontal: false, vertical: true)
            .background(BakerTheme.background).tint(BakerTheme.accent)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in session.refreshAccessibility() }
    }
    private var source: some View {
        Button(action: session.chooseSource) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(BakerTheme.surface)
                    if let preview = session.sourcePreview {
                        Image(nsImage: preview).resizable().scaledToFit().padding(8)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "macwindow.badge.plus").font(.system(size: 30, weight: .light))
                            Text(session.sourceName == nil ? "Choose Window…" : "Preview unavailable").font(BakerTypography.section)
                        }.foregroundStyle(.secondary)
                    }
                }.frame(height: 174).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.border))
                HStack(spacing: 6) {
                    Text(session.sourceName ?? "Capture source").font(BakerTypography.supporting)
                        .foregroundStyle(session.sourceName == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: session.sourceName == nil ? "plus" : "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(session.working).help("Choose or change the reader window")
            .accessibilityLabel(session.sourceName.map { "Change window: " + $0 } ?? "Choose reader window")
    }
}
