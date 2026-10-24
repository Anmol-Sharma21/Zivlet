import SwiftUI

/// The island group's accessibility text and callbacks, set by its host (design/19 §5.5, D-N12). Kept apart from the
/// chrome's model so a new spoken value (progress) redraws only the accessibility modifier, not the island (19b §6.2).
@Observable
final class IslandAccessibilityModel {
    var label = ""
    var value = ""
    var actionName = ""
    var onAction: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }
}

/// One accessibility group with a label, a value and the "show" action; accessibility focus entering or leaving
/// reaches the machine. It reads only its own model.
struct IslandAccessibility: ViewModifier {
    let model: IslandAccessibilityModel
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.label)
            .accessibilityValue(model.value)
            .accessibilityAction(named: model.actionName) { model.onAction() }
            .accessibilityFocused($focused)
            .onChange(of: focused) { _, now in model.onFocus(now) }
    }
}
