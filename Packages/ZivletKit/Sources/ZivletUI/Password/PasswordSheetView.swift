import SwiftUI
import ZivletCore
import ZivletNotch

/// The password sheet as the tool window's content (P2-101, plan 20c B4, D-M7-15; OWN-UI-1, 19b, 19c): the second
/// sheet's list, the fields with their eye buttons, the wrong-password line, the strength word with Suggest and Copy,
/// the notes, the batch switch, the switch to Change and the no-recovery footer. The first field takes the keyboard
/// when the window opens. A wrong password shakes the fields (Reduce Motion: their outline turns red for a second).
/// Text is white or white at 0.8 on the dark surface, never the system red (3.5:1 there).
struct PasswordSheetView: View {
    static let shakeDuration = 0.3
    static let flashDuration = Duration.seconds(1)
    static let errorSymbol = "xmark.circle"

    let state: PasswordSheetState
    @FocusState private var focus: PasswordField?
    @State private var flashing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: PasswordSheetModel { state.model }
    private var attempts: Int {
        if case .wrong(let attempt) = model.failure { return attempt }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.m) {
            if let title = model.retryTitle { PasswordRetryList(title: title, names: model.retryList) }
            fields
            if let error = model.errorLine { line(error, symbol: Self.errorSymbol, ink: IslandInk.primary) }
            if model.strength != nil || state.canSuggest { strengthRow }
            ForEach(model.notes, id: \.self) { line($0.text, symbol: $0.symbol, ink: IslandInk.secondary) }
            if model.offersRestrictions { PasswordRestrictionsSection(state: state) }
            if let label = model.sameForAllLabel {
                Toggle(label, isOn: Binding(get: { model.sameForAll }, set: state.setSameForAll))
                    .toggleStyle(PasswordCheckboxStyle())
            }
            if let label = model.changeSwitchLabel {
                Button(label, action: state.switchToChange)
                    .buttonStyle(.plain)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.primary)
                    .underline()
            }
            if let footer = model.footer {
                Text(footer)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { focus = model.fields.first }
        .onChange(of: model.mode) { focus = model.fields.first }
        .onChange(of: model.revealed) { if focus == nil { focus = model.fields.first } }
        .onChange(of: attempts) { wrongAttemptShown() }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.s) {
            ForEach(model.fields, id: \.self) { field in
                PasswordFieldRow(
                    field: field, text: binding(field), revealed: model.isRevealed(field), focus: $focus,
                    toggleReveal: { state.toggleReveal(field) }, labelled: model.labelsFields)
            }
        }
        .modifier(ShakeEffect(attempts: reduceMotion ? 0 : CGFloat(attempts)))
        .animation(.linear(duration: Self.shakeDuration), value: attempts)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.red, lineWidth: 2)
                .opacity(flashing ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var strengthRow: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            if let strength = model.strength {
                Text(PasswordCopy.strength(strength))
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
                    .accessibilityLabel(Self.strengthLabel(strength))
            }
            Spacer(minLength: 0)
            if state.canSuggest {
                Button(PasswordCopy.suggest, action: state.suggest).buttonStyle(.glass)
            }
            if model.strength != nil {
                CodeIconButton(symbol: "doc.on.doc", title: PasswordCopy.copy) { state.copyPassword() }
            }
        }
    }

    private func line(_ text: String, symbol: String, ink: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(IslandContentLook.TypeStyle.secondary)
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func binding(_ field: PasswordField) -> Binding<String> {
        switch field {
        case .password, .newPassword: Binding(get: { state.password }, set: { state.password = $0 })
        case .confirm: Binding(get: { state.confirm }, set: { state.confirm = $0 })
        case .current: Binding(get: { state.current }, set: { state.current = $0 })
        }
    }

    private func wrongAttemptShown() {
        focus = model.fields.first
        guard reduceMotion, attempts > 0 else { return }
        flashing = true
        Task {
            try? await Task.sleep(for: Self.flashDuration)
            flashing = false
        }
    }

    /// The strength word as VoiceOver reads it.
    static func strengthLabel(_ strength: PasswordRules.Strength) -> String {
        "Password strength: \(PasswordCopy.strength(strength))"
    }

    /// The VoiceOver labels of the sheet's controls in `model`, in order (the fields, their eye buttons, Suggest and
    /// Copy, the batch switch, the switch to Change).
    static func controlLabels(_ model: PasswordSheetModel, canSuggest: Bool) -> [String] {
        let fields = model.fields.flatMap { [$0.label, PasswordFieldRow.eyeLabel(revealed: model.isRevealed($0))] }
        let suggest = canSuggest && model.setsPassword ? [PasswordCopy.suggest] : []
        let copy = model.strength != nil ? [PasswordCopy.copy] : []
        return fields + suggest + copy + [model.sameForAllLabel, model.changeSwitchLabel].compactMap { $0 }
    }
}

/// The second sheet's heading and the files that did not open.
struct PasswordRetryList: View {
    let title: String
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
            Text(title).font(IslandContentLook.TypeStyle.primary).foregroundStyle(IslandInk.primary)
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
