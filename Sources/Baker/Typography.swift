import SwiftUI

/// A shared minimum for readable controls and supporting text in Baker windows.
enum BakerTypography {
    static let title = Font.system(size: 22, weight: .semibold)
    static let control = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let supporting = Font.system(size: 12)
    static let section = Font.system(size: 13, weight: .semibold)
    static let sidebar = Font.system(size: 13, weight: .medium)
}

struct BakerSearchField: View {
    let prompt: String
    @Binding var text: String
    var searching: Bool
    @FocusState private var focused: Bool

    init(_ prompt: String, text: Binding<String>, searching: Bool = false) {
        self.prompt = prompt
        _text = text
        self.searching = searching
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain).focused($focused)
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
            if searching { ProgressView().controlSize(.small).accessibilityLabel("Searching") }
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .accessibilityLabel("Clear search").help("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(minHeight: 34)
        .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? BakerTheme.accent : BakerTheme.border, lineWidth: focused ? 2 : 1).allowsHitTesting(false) }
    }
}

/// Shared action geometry; menus and segmented controls retain their native styles.
struct BakerButtonStyle: ButtonStyle {
    var prominent = false
    var expands = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(BakerTypography.control).lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 32, maxWidth: expands ? .infinity : nil, minHeight: 32, maxHeight: 32)
            .foregroundStyle(prominent ? BakerTheme.selectionForeground : Color.primary)
            .background(prominent ? BakerTheme.accent : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? BakerTheme.accent : Color.primary.opacity(prominent ? 0 : 0.15), lineWidth: focused ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? (configuration.isPressed && prominent ? 0.82 : 1) : 0.4)
            .animation(BakerMotion.selection(reduced: reduceMotion), value: configuration.isPressed)
    }
}

/// Equal icon slots keep toolbar symbols aligned without resizing their labels.
struct BakerToolbarLabelStyle: LabelStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 14, weight: .medium)).frame(width: 16, height: 20)
            if !compact { configuration.title.fixedSize() }
        }
    }
}

/// Settings share one surface, spacing rhythm and trailing control alignment.
struct BakerSettingsSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(BakerTypography.section) }
            content
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BakerTheme.border))
    }
}
