import SwiftUI
import ZivletCore
import ZivletNotch

/// Lock's restrictions (17a §3.1, D-M7-20; OWN-UI-1): printing, copying and editing. Choosing any shows the owner
/// password the app made, once, with Copy, and the line saying restrictions are not security. White and white at 0.8 on
/// the dark surface, as the rest of the sheet; the choices draw no accent colour (D-M7-62). VoiceOver reads the owner
/// password as the value of its caption.
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
                    .accessibilityHidden(true)  // the choice's own title carries it
                PasswordSegmentedChoice(
                    title: PasswordCopy.printing,
                    choices: Array(zip(Self.printingValues, PasswordCopy.printingChoices)).map {
                        (value: $0, label: $1)
                    },
                    selection: printing)
            }
            checkbox(PasswordCopy.allowCopying, isOn: copying)
            checkbox(PasswordCopy.allowEditing, isOn: editing)
            if restrictions != .none, let owner = state.ownerPassword { ownerRow(owner) }
        }
    }

    private func checkbox(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn).toggleStyle(PasswordCheckboxStyle())
    }

    private func ownerRow(_ owner: String) -> some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
            Text(PasswordCopy.ownerShownOnce)
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(IslandInk.secondary)
                .accessibilityHidden(true)  // read as the password's label
            HStack(spacing: IslandContentLook.Spacing.s) {
                let read = Self.ownerAccessibility(owner)
                Text(owner)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(IslandInk.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .accessibilityLabel(read.label)
                    .accessibilityValue(read.value)
                Spacer(minLength: 0)
                CodeIconButton(symbol: "doc.on.doc", title: PasswordCopy.copyOwner) { state.copyOwnerPassword() }
            }
            Text(PasswordCopy.notSecurity)
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(IslandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What VoiceOver reads for the owner password: its caption, then the password itself (it is shown only once).
    static func ownerAccessibility(_ owner: String) -> (label: String, value: String) {
        (PasswordCopy.ownerShownOnce, owner)
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
