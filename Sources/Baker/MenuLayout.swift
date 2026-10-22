import AppKit
import SwiftUI

struct BakerMenuGroup: Identifiable {
    let id: String
    let title: String
    let entries: [(id: String, title: String)]
    static let all: [Self] = [
        .init(id: "capture", title: "Capture", entries: [("captureAll", "All"), ("captureRegion", "Area"), ("captureWindow", "Window…"), ("repeatCaptureArea", "Repeat Area"), ("captureScroll", "Scrolling"), ("captureText", "Text"), ("captureFormula", "Formula"), ("recordScreen", "Record…")]),
        .init(id: "files", title: "Clipboard & Files", entries: [("openImage", "Open Files"), ("newFormulaWorkspace", "Formula Workspace"), ("pasteImage", "Open Clipboard Image"), ("readClipboard", "Read Clipboard Text")]),
        .init(id: "recent", title: "Recent", entries: [("openCaptureFolder", "Open Capture Folder"), ("showPreview", "Last Capture"), ("showHistory", "Capture History"), ("showResult", "Last Result"), ("showExport", "Last Export")])
    ]
}

struct BakerMenuLayout: Codable, Equatable {
    var version = 3
    var groups: [String] = []
    var entries: [String: [String]] = [:]
    var hidden: Set<String> = []
    static let preference = PreferenceKeys.menuLayout.name
    static func load(from preferences: UserDefaults = .standard) -> Self {
        guard let data = preferences.data(forKey: preference),
              let value = try? JSONDecoder().decode(Self.self, from: data), (1...3).contains(value.version) else { return Self() }
        return value.migrated
    }
    var migrated: Self {
        var value = self
        if version == 1 {
            value.groups.removeAll { $0 == "record" }
            value.entries.removeValue(forKey: "record")
            let bothHidden = value.hidden.contains("recordVideo") && value.hidden.contains("recordGIF")
            value.hidden.subtract(["recordVideo", "recordGIF"])
            if bothHidden { value.hidden.insert("recordScreen") }
        }
        if version < 3 {
            var recent = value.entries["recent"] ?? []
            recent.removeAll { $0 == "openCaptureFolder" }
            recent.insert("openCaptureFolder", at: 0)
            value.entries["recent"] = recent
            value.version = 3
        }
        return value
    }
    func save(to preferences: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { preferences.set(data, forKey: Self.preference) }
    }
    func ordered(_ values: [String], saved: [String]) -> [String] {
        var seen = Set<String>()
        return (saved + values).filter { values.contains($0) && seen.insert($0).inserted }
    }
    /// Move within one validated scope. Unknown IDs and cross-group moves leave the layout unchanged.
    mutating func move(_ id: String, to target: String, group: String? = nil) -> Bool {
        let definition = BakerMenuGroup.all.first { $0.id == group }
        if group != nil && definition == nil { return false }
        var ids = definition.map { orderedEntries($0) } ?? orderedGroups.map(\.id)
        guard id != target, let source = ids.firstIndex(of: id), let destination = ids.firstIndex(of: target) else { return false }
        ids.remove(at: source); ids.insert(id, at: destination)
        if let group { entries[group] = ids } else { groups = ids }
        return true
    }

    var orderedGroups: [BakerMenuGroup] {
        ordered(BakerMenuGroup.all.map(\.id), saved: groups).compactMap { id in BakerMenuGroup.all.first { $0.id == id } }
    }
    func orderedEntries(_ group: BakerMenuGroup) -> [String] { ordered(group.entries.map(\.id), saved: entries[group.id] ?? []) }
}

@MainActor private final class MenuLayoutDraft: ObservableObject {
    @Published var value: BakerMenuLayout
    @Published var applied: BakerMenuLayout
    private let preferences: UserDefaults
    private let dragSession = UUID().uuidString
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let saved = BakerMenuLayout.load(from: preferences)
        value = saved; applied = saved
    }
    func apply() { value.save(to: preferences); applied = value }
    func payload(_ id: String, group: String?) -> String { [dragSession, group ?? "groups", id].joined(separator: "/") }
    func drop(_ payloads: [String], on target: String, group: String?) -> Bool {
        guard payloads.count == 1 else { return false }
        let parts = payloads[0].split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == dragSession, parts[1] == (group ?? "groups") else { return false }
        return value.move(parts[2], to: target, group: group)
    }
    func move(_ id: String, group: String?, by offset: Int) {
        let ids = group.flatMap { name in BakerMenuGroup.all.first { $0.id == name } }.map { value.orderedEntries($0) } ?? value.orderedGroups.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        _ = value.move(id, to: ids[index + offset], group: group)
    }
}

struct MenuLayoutSettings: View {
    @StateObject private var draft: MenuLayoutDraft
    init(preferences: UserDefaults = .standard) { _draft = StateObject(wrappedValue: MenuLayoutDraft(preferences: preferences)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Drag the handles to reorder groups or commands within a group. Untick a command to hide it.")
                .font(BakerTypography.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(draft.value.orderedGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(group.title).font(.headline)
                        Spacer()
                        handle(group.id, name: group.title, group: nil)
                    }.contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in draft.drop(items, on: group.id, group: nil) }
                    ForEach(draft.value.orderedEntries(group), id: \.self) { id in
                        HStack {
                            Toggle(group.entries.first(where: { $0.id == id })?.title ?? id,
                                   isOn: Binding(get: { !draft.value.hidden.contains(id) }, set: { visible in
                                if visible { draft.value.hidden.remove(id) } else { draft.value.hidden.insert(id) }
                            }))
                            Spacer()
                            handle(id, name: group.entries.first(where: { $0.id == id })?.title ?? id, group: group.id)
                        }.contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in draft.drop(items, on: id, group: group.id) }
                    }
                }.padding(18).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Settings, Quit and active Stop/Cancel commands remain available. Hidden commands keep their assigned global shortcuts.")
                .font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Restore Defaults") { draft.value = BakerMenuLayout() }
                Spacer()
                Button("Revert") { draft.value = draft.applied }.disabled(draft.value == draft.applied)
                Button("Apply", action: draft.apply).buttonStyle(.borderedProminent).disabled(draft.value == draft.applied)
            }
            Text("Apply updates the next menu opening. No restart is needed.").font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func handle(_ id: String, name: String, group: String?) -> some View {
        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            .frame(width: 30, height: 24).contentShape(Rectangle())
            .draggable(draft.payload(id, group: group))
            .help("Drag to move \(name); right-click for move commands")
            .accessibilityLabel("Reorder \(name)")
            .accessibilityAction(named: "Move up") { draft.move(id, group: group, by: -1) }
            .accessibilityAction(named: "Move down") { draft.move(id, group: group, by: 1) }
            .contextMenu {
                Button("Move Up") { draft.move(id, group: group, by: -1) }
                Button("Move Down") { draft.move(id, group: group, by: 1) }
            }
    }
}
