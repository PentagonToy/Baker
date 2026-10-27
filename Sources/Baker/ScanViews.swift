import AppKit
import SwiftUI
import BakerCore
import ApplicationServices

@MainActor private final class ScanControlsState: ObservableObject { @Published var options = false }
@MainActor private final class ScanReviewState: ObservableObject { @Published var confirmRemove = false; @Published var confirmDiscard = false }
@MainActor private final class ScanPreviewState: ObservableObject { @Published var image: NSImage?; @Published var failed = false }

struct ScanControls: View {
    @ObservedObject var session: ScanSession
    @StateObject private var state = ScanControlsState()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Scan", systemImage: "doc.viewfinder").font(BakerTypography.section)
                Text(session.pageCountLabel).font(BakerTypography.supporting).foregroundStyle(.secondary)
                Spacer()
                Button { state.options.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Auto turn options").accessibilityLabel("Scan options")
                    .popover(isPresented: $state.options) { autoOptions }
            }
            HStack(spacing: 8) {
                if session.automaticSession {
                    Button { session.toggleAuto() } label: {
                        Label(session.automatic ? "Pause" : "Resume", systemImage: session.automatic ? "pause.fill" : "play.fill")
                    }.buttonStyle(BakerButtonStyle(prominent: true, expands: true)).disabled(!session.automatic && !session.canAdd)
                } else {
                    Button { session.addPage() } label: { Label("Add Page", systemImage: "plus") }
                        .buttonStyle(BakerButtonStyle(prominent: true, expands: true)).disabled(!session.canAdd)
                }
                Button("Review", action: session.review).buttonStyle(BakerButtonStyle()).disabled(session.pages.isEmpty && session.working)
            }
            Text(session.message).font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).frame(width: 448, height: 126).background(BakerTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BakerTheme.border)).tint(BakerTheme.accent)
    }
    private var autoOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto turn").font(BakerTypography.section)
            HStack {
                Text("Delay")
                Spacer()
                ScanDelayField(seconds: $session.turnDelay).disabled(session.automatic)
            }
            if AXIsProcessTrusted() {
                Button(session.automatic ? "Pause Auto Turn" : "Start Auto Turn") { state.options = false; session.toggleAuto() }
                    .buttonStyle(BakerButtonStyle(prominent: true, expands: true)).disabled(!session.automatic && !session.canAdd)
            } else {
                Text("Control access needed")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Allow…", action: session.openAccessibilitySettings).buttonStyle(BakerButtonStyle())
            }
        }.padding(16).frame(width: 300)
    }
}

struct ScanReview: View {
    @ObservedObject var session: ScanSession
    @StateObject private var state = ScanReviewState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var page: ScanPage? { session.pages.first { $0.id == session.selected } }
    private var index: Int { session.pages.firstIndex { $0.id == session.selected } ?? 0 }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Scan", systemImage: "doc.viewfinder").font(BakerTypography.section)
                Text(session.pageCountLabel).foregroundStyle(.secondary).font(BakerTypography.supporting)
                Menu {
                    Button("Discard Scan…", role: .destructive) { state.confirmDiscard = true }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(session.working).accessibilityLabel("Scan actions")
                Spacer()
                Button { session.continueCapture() } label: { Label("Add Pages", systemImage: "plus") }
                    .buttonStyle(BakerButtonStyle()).disabled(session.working)
                Button("Save PDF…") { session.savePDF() }.buttonStyle(BakerButtonStyle(prominent: true))
                    .disabled(session.pages.isEmpty || session.working)
            }.padding(16)
            Divider()
            Group {
                if let page {
                    ScanPagePreview(draft: session.draft, page: page, maximum: 1200)
                        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.viewfinder").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text("No pages yet").font(BakerTypography.title)
                        Text("Choose a reader window to add pages.").foregroundStyle(.secondary)
                        Button("Choose Window…") { session.chooseSource() }.buttonStyle(BakerButtonStyle(prominent: true))
                            .disabled(session.working)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.background(BakerTheme.surface)
            if !session.pages.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Text("Page \(index + 1) of \(session.pages.count)").font(BakerTypography.supporting).foregroundStyle(.secondary)
                    Spacer()
                    Button { session.moveSelected(-1) } label: { Image(systemName: "arrow.left") }
                        .disabled(index == 0 || session.working).help("Move page earlier").accessibilityLabel("Move page earlier")
                    Button { session.moveSelected(1) } label: { Image(systemName: "arrow.right") }
                        .disabled(index + 1 >= session.pages.count || session.working).help("Move page later").accessibilityLabel("Move page later")
                    Button("Retake") { session.continueCapture(retake: session.selected) }.disabled(session.working)
                    Button { state.confirmRemove = true } label: { Image(systemName: "trash") }
                        .disabled(session.working).help("Remove this page").accessibilityLabel("Remove page")
                }.buttonStyle(BakerButtonStyle()).padding(.horizontal, 16).padding(.vertical, 10)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(Array(session.pages.enumerated()), id: \.element.id) { i, page in
                                Button {
                                    withAnimation(BakerMotion.selection(reduced: reduceMotion)) { session.selected = page.id }
                                } label: {
                                    VStack(spacing: 5) {
                                        ScanPagePreview(draft: session.draft, page: page, maximum: 160).frame(width: 76, height: 72)
                                        Text("\(i + 1)").font(BakerTypography.supporting).foregroundStyle(.secondary)
                                    }.padding(6).background(session.selected == page.id ? BakerTheme.accent.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(session.selected == page.id ? BakerTheme.accent : .clear))
                                }.buttonStyle(.plain).accessibilityLabel("Page \(i + 1)")
                                    .accessibilityAddTraits(session.selected == page.id ? .isSelected : []).id(page.id)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 8)
                    }.frame(height: 128).onChange(of: session.selected) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            Divider()
            HStack(spacing: 12) {
                if session.phase == .exporting {
                    ProgressView().controlSize(.small)
                    Text(session.message).font(BakerTypography.supporting).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel Saving", action: session.cancelExport).buttonStyle(BakerButtonStyle())
                } else {
                    Toggle("Searchable text", isOn: $session.searchable).font(BakerTypography.supporting).disabled(session.working)
                        .help("Use on-device text recognition while saving. The page images stay unchanged.")
                    Spacer()
                    Text(session.message).font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(16)
        }.background(BakerTheme.background).tint(BakerTheme.accent)
            .alert("Discard this scan?", isPresented: $state.confirmDiscard) {
                Button("Keep Scan", role: .cancel) {}
                Button("Discard", role: .destructive, action: session.discard)
            } message: { Text("The working pages will be removed. Saved PDFs are kept.") }
            .alert("Remove this page?", isPresented: $state.confirmRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove Page", role: .destructive, action: session.removeSelected)
            } message: { Text("You can capture it again before saving the PDF.") }
    }
}

private struct ScanPagePreview: View {
    let draft: ScanDocument
    let page: ScanPage
    let maximum: Int
    @StateObject private var state = ScanPreviewState()
    var body: some View {
        Group {
            if let image = state.image { Image(nsImage: image).resizable().scaledToFit() }
            else if state.failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).accessibilityLabel("Page preview unavailable") }
            else { ProgressView().controlSize(.small) }
        }.task(id: page.id) {
            state.image = nil; state.failed = false
            do {
                let raster = try await draft.preview(page, maximum: maximum)
                try Task.checkCancellation(); state.image = NSImage(cgImage: raster, size: .zero)
            } catch { if !Task.isCancelled { state.failed = true } }
        }.onDisappear { state.image = nil }
    }
}
