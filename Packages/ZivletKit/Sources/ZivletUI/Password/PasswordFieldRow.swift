import SwiftUI
import ZivletNotch

/// One password field with its eye button (P2-101): a `SecureField`, or a `TextField` on the same text while the
/// passwords are revealed. Return submits the window (Apply, when it is on).
struct PasswordFieldRow: View {
    let field: PasswordField
    @Binding var text: String
    let revealed: Bool
    let focus: FocusState<PasswordField?>.Binding
    let toggleReveal: () -> Void
    @Environment(\.toolWindowSubmit) private var submit

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            entry
                .textFieldStyle(.roundedBorder)
                .font(IslandContentLook.TypeStyle.secondary)
                .focused(focus, equals: field)
                .onSubmit { submit() }
                .accessibilityLabel(field.label)
            CodeIconButton(symbol: Self.eyeSymbol(revealed: revealed), title: Self.eyeLabel(revealed: revealed)) {
                toggleReveal()
            }
        }
    }

    @ViewBuilder private var entry: some View {
        if revealed {
            TextField(field.label, text: $text)
                .autocorrectionDisabled()
        } else {
            SecureField(field.label, text: $text)
        }
    }

    static func eyeSymbol(revealed: Bool) -> String { revealed ? "eye.slash" : "eye" }
    static func eyeLabel(revealed: Bool) -> String { revealed ? PasswordCopy.hide : PasswordCopy.show }
}

/// A wrong password's shake: three swings of 6 pt while `attempts` moves by one (0.3 s, set by the caller).
struct ShakeEffect: GeometryEffect {
    static let amplitude: CGFloat = 6
    static let swings: CGFloat = 3
    var attempts: CGFloat

    var animatableData: CGFloat {
        get { attempts }
        set { attempts = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: Self.amplitude * sin(attempts * .pi * 2 * Self.swings), y: 0))
    }
}
