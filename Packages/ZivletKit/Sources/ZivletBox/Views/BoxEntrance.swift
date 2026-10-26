import SwiftUI
import ZivletNotchCore

/// How the panel's card enters (19c D-BL12): it grows from 0.96 at its top while it fades in, inside the island's
/// expand spring; under Reduce Motion it only fades, for 0.18 s. It leaves at once: the panel is ordered out.
struct BoxEntrance: ViewModifier {
    let reduceMotion: Bool
    @State private var entered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(entered || reduceMotion ? 1 : BoxLook.Motion.enterScale, anchor: .top)
            .opacity(entered ? 1 : 0)
            .onAppear { withAnimation(Self.animation(reduceMotion: reduceMotion)) { entered = true } }
    }

    /// The island's expand curve: its spring, or its fade under Reduce Motion.
    static func animation(reduceMotion: Bool) -> Animation {
        switch IslandMotion(reduceMotion: reduceMotion).expand {
        case .spring(let response, let damping): .spring(response: response, dampingFraction: damping)
        case .fade(let seconds): .easeOut(duration: seconds)
        }
    }
}
