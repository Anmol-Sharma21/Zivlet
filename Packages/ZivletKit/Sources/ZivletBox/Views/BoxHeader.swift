import SwiftUI
import ZivletNotch
import ZivletShelfCore

/// The header (19c D-BL4, §4.1): the box symbol, the count or selection, the size and any missing count; on the
/// right the Attention buttons, the view switch and the overflow menu. No title.
struct BoxHeader: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    private var busyLine: String? {
        if case .busy(let verb, _) = model.presentation.overlay { return verb }
        return nil
    }

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: BoxSymbols.box)
                .font(IslandContentLook.Symbol.tab)
                .foregroundStyle(IslandInk.primary)
                .accessibilityHidden(true)
            Text(busyLine ?? model.primaryLine)
                .font(IslandContentLook.TypeStyle.primary)
                .foregroundStyle(IslandInk.primary)
                .lineLimit(1)
            if busyLine == nil {
                Text(model.secondaryLine).font(IslandContentLook.TypeStyle.secondary).foregroundStyle(
                    IslandInk.secondary
                )
                .lineLimit(1).fixedSize()
                if let missing = model.missingLine {
                    Text(missing).font(IslandContentLook.TypeStyle.secondary).foregroundStyle(IslandInk.secondary)
                        .lineLimit(1).fixedSize()
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: BoxLook.Panel.headerHeight)
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: IslandContentLook.Spacing.xs) {
            if model.canLocate { BoxIconButton(press: .locate, action: press) }
            if model.missingCount > 0 { BoxIconButton(press: .removeMissing, action: press) }
            BoxIconButton(press: model.viewMode == .grid ? .list : .grid, action: press)
            BoxOverflowMenu(press: press)
        }
    }
}

/// The commands that do not fit the bar (19c D-BL5): Copy to…, Copy Paths, Remove from Box, Clear Box.
struct BoxOverflowMenu: View {
    let press: (BoxPress) -> Void

    var body: some View {
        Menu {
            ForEach(BoxPress.overflow, id: \.self.menuID) { item in
                Button(BoxCopy.title(item)) { press(item) }
            }
        } label: {
            BoxSymbolLabel(symbol: BoxSymbols.more)
        }
        .menuStyle(.button)
        .buttonStyle(IslandIconButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help(BoxCopy.title(.more))
        .accessibilityLabel(BoxCopy.title(.more))
    }
}

extension BoxPress {
    /// A stable identity for menu rows.
    var menuID: String { BoxCopy.title(self) }
}
