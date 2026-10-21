import AppKit
import ZivletSettings
import ZivletTrigger
import ZivletUI
import ZivletWheel

/// The key legend beside the wheel for the first three real drags after onboarding (P1-47): shown with the wheel,
/// hidden with it, and each drag that showed it counts down `onboarding.practiceDragsLeft`.
final class CoachWiring {
    private let store: SettingsStore
    private let panel = KeyLegendPanel()
    private var shownThisDrag = false

    init(store: SettingsStore) {
        self.store = store
    }

    /// Called with every wheel effect, after the wheel applied it.
    func observe(_ effect: TriggerEffect, wheel: WheelController) {
        switch effect {
        case .show:
            guard KeyLegend.shows(store.current.onboarding) else { return }
            panel.show(KeyLegend.text(store.current.trigger.bindings), beside: wheel.panelFrame)
            shownThisDrag = true
        case .hide:
            panel.hide()
            guard shownThisDrag else { return }
            shownThisDrag = false
            store.update { $0.with(\.onboarding, KeyLegend.counting($0.onboarding)) }
        default: break
        }
    }
}
