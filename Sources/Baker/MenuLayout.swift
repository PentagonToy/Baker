import AppKit
import SwiftUI

struct BakerMenuGroup: Identifiable {
    let id: String
    let title: String
    let entries: [(id: String, title: String)]
    static let all: [Self] = [
        .init(id: "capture", title: "Capture", entries: [("captureAll", "All"), ("captureRegion", "Area"), ("captureScroll", "Scrolling"), ("captureText", "Text"), ("captureFormula", "Formula")]),
        .init(id: "record", title: "Record", entries: [("recordVideo", "Video"), ("recordGIF", "GIF")]),
        .init(id: "files", title: "Clipboard & Files", entries: [("openImage", "Open Files"), ("newFormulaWorkspace", "Formula Workspace"), ("pasteImage", "Open Clipboard Image"), ("readClipboard", "Read Clipboard Text")]),
        .init(id: "recent", title: "Recent", entries: [("showPreview", "Last Capture"), ("showHistory", "Capture History"), ("openCaptureFolder", "Open Capture Folder"), ("showResult", "Last Result"), ("showExport", "Last Export")])
    ]
}

struct BakerMenuLayout: Codable, Equatable {
    var version = 1
    var groups: [String] = []
    var entries: [String: [String]] = [:]
    var hidden: Set<String> = []
    static let preference = "bakerMenuLayout"
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: preference),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1 else { return Self() }
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.preference) }
    }
    func ordered(_ values: [String], saved: [String]) -> [String] {
        var seen = Set<String>()
        return (saved + values).filter { values.contains($0) && seen.insert($0).inserted }
    }
    var orderedGroups: [BakerMenuGroup] {
        ordered(BakerMenuGroup.all.map(\.id), saved: groups).compactMap { id in BakerMenuGroup.all.first { $0.id == id } }
    }
    func orderedEntries(_ group: BakerMenuGroup) -> [String] { ordered(group.entries.map(\.id), saved: entries[group.id] ?? []) }
}

@MainActor private final class MenuLayoutDraft: ObservableObject {
    @Published var value = BakerMenuLayout.load()
    @Published var applied = BakerMenuLayout.load()
    func apply() { value.save(); applied = value }
    func moveGroup(_ id: String, by offset: Int) {
        var ids = value.orderedGroups.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); value.groups = ids
    }
    func moveEntry(_ id: String, group: BakerMenuGroup, by offset: Int) {
        var ids = value.orderedEntries(group)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); value.entries[group.id] = ids
    }
}

struct MenuLayoutSettings: View {
    @StateObject private var draft = MenuLayoutDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose the order and visible commands in Baker’s menu-bar menu.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(draft.value.orderedGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(group.title).font(.headline)
                        Spacer()
                        moveButtons(index: draft.value.orderedGroups.firstIndex(where: { $0.id == group.id }) ?? 0,
                                    count: draft.value.orderedGroups.count, name: group.title) { draft.moveGroup(group.id, by: $0) }
                    }
                    ForEach(draft.value.orderedEntries(group), id: \.self) { id in
                        HStack {
                            Toggle(group.entries.first(where: { $0.id == id })?.title ?? id,
                                   isOn: Binding(get: { !draft.value.hidden.contains(id) }, set: { visible in
                                if visible { draft.value.hidden.remove(id) } else { draft.value.hidden.insert(id) }
                            }))
                            Spacer()
                            moveButtons(index: draft.value.orderedEntries(group).firstIndex(of: id) ?? 0,
                                        count: group.entries.count, name: group.entries.first(where: { $0.id == id })?.title ?? id) {
                                draft.moveEntry(id, group: group, by: $0)
                            }
                        }
                    }
                }.padding(18).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Settings, Quit and active Stop/Cancel commands remain available. Hidden commands keep their assigned global shortcuts.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Restore Defaults") { draft.value = BakerMenuLayout() }
                Spacer()
                Button("Revert") { draft.value = draft.applied }.disabled(draft.value == draft.applied)
                Button("Apply", action: draft.apply).buttonStyle(.borderedProminent).disabled(draft.value == draft.applied)
            }
            Text("Apply updates the next menu opening. No restart is needed.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func moveButtons(index: Int, count: Int, name: String, move: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).help("Move \(name) up").accessibilityLabel("Move \(name) up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(index + 1 == count).help("Move \(name) down").accessibilityLabel("Move \(name) down")
        }.buttonStyle(.borderless)
    }
}
