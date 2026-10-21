import SwiftUI
import ZivletCore

/// Pages 2 and 3: the real trigger and wheel, tried on a sample file (03b §8.2).
struct PracticePage: View {
    let model: OnboardingModel
    let modes: [WheelMode]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: Self.title(modes), lead: Self.lead(modes))
            ForEach(modes, id: \.self) { mode in
                HStack(spacing: 12) {
                    KeyCap(symbol: model.keyCap(for: mode))
                    Text(Self.step(mode))
                }
            }
        }
    }

    static func title(_ modes: [WheelMode]) -> String {
        modes == [.convert] ? "Try converting" : "Tools and actions"
    }

    static func lead(_ modes: [WheelMode]) -> String {
        modes == [.convert]
            ? "Start dragging the sample, tap the key once without letting go, then drop on a slice."
            : "The same gesture with another key opens the other wheels."
    }

    static func step(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: "Convert: turn the file into another format."
        case .tools: "Tools: resize, compress and more."
        case .actions: "Actions: copy, move, AirDrop or open in Terminal."
        }
    }
}
