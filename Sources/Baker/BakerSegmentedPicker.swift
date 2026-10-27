import AppKit
import SwiftUI

/// A single-choice native control with equal segments, keyboard navigation and system accessibility.
struct BakerSegmentedPicker<Selection: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Selection
    let choices: [(String, Selection)]
    @Environment(\.isEnabled) private var isEnabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: choices.map(\.0), trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded; control.segmentDistribution = .fillEqually; control.controlSize = .regular
        control.selectedSegmentBezelColor = NSColor(BakerTheme.accent)
        control.font = .systemFont(ofSize: 13, weight: .medium)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.segmentCount != choices.count { control.segmentCount = choices.count }
        for (index, choice) in choices.enumerated() {
            if control.label(forSegment: index) != choice.0 { control.setLabel(choice.0, forSegment: index) }
            control.setEnabled(isEnabled, forSegment: index)
        }
        control.selectedSegment = choices.firstIndex { $0.1 == selection } ?? -1
        control.isEnabled = isEnabled; control.setAccessibilityLabel(title)
    }
    final class Coordinator: NSObject {
        var parent: BakerSegmentedPicker
        init(_ parent: BakerSegmentedPicker) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.choices.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.choices[sender.selectedSegment].1
        }
    }
}
