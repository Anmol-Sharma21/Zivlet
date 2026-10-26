import SwiftUI
import ZivletNotch

/// The tray's drop target (19c §3.4, §4.2): `tray.and.arrow.down.fill`, "Add 3" and, when the box is not empty,
/// "12 in box" on the right. One row in the island's toast frame; no outline, no accent colour (D-BL7).
struct TrayDropRow: View {
    let count: Int
    let inBox: Int

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: BoxSymbols.dropHere).font(IslandContentLook.Symbol.toast)
                .foregroundStyle(IslandInk.primary).accessibilityHidden(true)
            Text(BoxCopy.add(count)).font(IslandContentLook.TypeStyle.primary).foregroundStyle(IslandInk.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if inBox > 0 {
                Text(BoxCopy.inBox(inBox)).font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary).lineLimit(1).layoutPriority(1)
            }
        }
        .padding(.horizontal, IslandContentLook.Spacing.m)
        .frame(maxWidth: .infinity)
        .frame(height: IslandContentLook.Spacing.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoxSpeech.dropTarget(count))
    }
}

/// The result toast's row: the check mark or the triangle, the line, and Undo when the drop can be undone.
struct TrayToastRow: View {
    let toast: TrayToastModel
    let undo: () -> Void

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: toast.failed ? BoxSymbols.failed : BoxSymbols.saved)
                .font(IslandContentLook.Symbol.toast).foregroundStyle(IslandInk.primary).accessibilityHidden(true)
            Text(toast.text).font(IslandContentLook.TypeStyle.primary).foregroundStyle(IslandInk.primary)
                .lineLimit(1).truncationMode(.tail).accessibilityLabel(toast.spoken)
            Spacer(minLength: 0)
            if !toast.undoIDs.isEmpty {
                Button(action: undo) { BoxSymbolLabel(symbol: BoxSymbols.undo) }
                    .buttonStyle(IslandIconButtonStyle())
                    .help(BoxCopy.undo).accessibilityLabel(BoxCopy.undo)
            }
        }
        .padding(.horizontal, IslandContentLook.Spacing.m)
        .frame(maxWidth: .infinity)
        .frame(height: IslandContentLook.Spacing.rowHeight)
    }
}
