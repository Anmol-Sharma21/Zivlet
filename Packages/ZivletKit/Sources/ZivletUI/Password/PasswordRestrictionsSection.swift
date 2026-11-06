import SwiftUI
import ZivletCore
import ZivletNotch

/// Lock's restrictions (17a §3.1, D-M7-20; OWN-UI-1): printing, copying and editing. Choosing any shows the owner
/// password the app made, once, with Copy, and the line saying restrictions are not security. White and white at 0.8 on
/// the dark surface, as the rest of the sheet.
struct PasswordRestrictionsSection: View {
    static let printingValues: [PDFRestrictions.Printing] = [.none, .low, .full]

    let state: PasswordSheetState

    private var restrictions: PDFRestrictions { state.restrictions }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.s) {
            VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
                Text(PasswordCopy.printing)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.primary)
                Picker(PasswordCopy.printing, selection: printing) {
                    ForEach(Array(Self.printingValues.enumerated()), id: \.offset) { index, value in
                        Text(PasswordCopy.printingChoices[index]).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(PasswordCopy.printing)
            }
            checkbox(PasswordCopy.allowCopying, isOn: copying)
            checkbox(PasswordCopy.allowEditing, isOn: editing)
            if restrictions != .none, let owner = state.ownerPassword { ownerRow(owner) }
        }
    }

    private func checkbox(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(IslandContentLook.TypeStyle.secondary)
            .foregroundStyle(IslandInk.primary)
    }

    private func ownerRow(_ owner: String) -> some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
            Text(PasswordCopy.ownerShownOnce)
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(IslandInk.secondary)
            HStack(spacing: IslandContentLook.Spacing.s) {
                Text(owner)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(IslandInk.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .accessibilityLabel(PasswordCopy.ownerShownOnce)
                Spacer(minLength: 0)
                CodeIconButton(symbol: "doc.on.doc", title: PasswordCopy.copyOwner) { state.copyOwnerPassword() }
            }
            Text(PasswordCopy.notSecurity)
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(IslandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var printing: Binding<PDFRestrictions.Printing> {
        Binding(
            get: { restrictions.printing },
            set: {
                state.setRestrictions(
                    PDFRestrictions(printing: $0, copying: restrictions.copying, editing: restrictions.editing))
            })
    }

    private var copying: Binding<Bool> {
        Binding(
            get: { restrictions.copying },
            set: {
                state.setRestrictions(
                    PDFRestrictions(printing: restrictions.printing, copying: $0, editing: restrictions.editing))
            })
    }

    private var editing: Binding<Bool> {
        Binding(
            get: { restrictions.editing },
            set: {
                state.setRestrictions(
                    PDFRestrictions(printing: restrictions.printing, copying: restrictions.copying, editing: $0))
            })
    }
}
