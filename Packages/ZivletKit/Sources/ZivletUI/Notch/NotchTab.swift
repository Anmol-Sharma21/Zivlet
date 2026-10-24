import SwiftUI
import ZivletNotchCore

/// The collapsed island's tab (design/19 §3.4, §4.3): the target's family symbol left, "3 jobs" in the middle, the ring,
/// stepped glyph, check mark or error glyph right. It reads the board as last published, which changes only when
/// the board says `redraw` or the layout changes (D-N7). The island group speaks for it, so it is hidden from
/// VoiceOver itself.
struct NotchTab: View {
    let model: NotchHUDModel
    let display: UInt32
    /// The tab sits in the band under a housing, not in a pill.
    let underHousing: Bool

    /// 8 pt under a housing; 12 pt in a pill, clear of its round ends (19b §3.1).
    static func sideInset(underHousing: Bool) -> CGFloat {
        underHousing ? NotchLook.Spacing.s : NotchLook.Spacing.m
    }

    var body: some View {
        HStack(spacing: NotchLook.Spacing.s) {
            if let tab = model.board.tab(on: display) {
                NotchTabIcon(icon: tab.icon)
                Spacer(minLength: 0)
                if let count = tab.count {
                    Text(count).font(NotchLook.TypeStyle.count).foregroundStyle(NotchInk.primary).lineLimit(1)
                }
                Spacer(minLength: 0)
                NotchStatusGlyph(tab: tab)
            }
        }
        .padding(.horizontal, Self.sideInset(underHousing: underHousing))
        .frame(maxWidth: .infinity)
        .frame(height: NotchLook.Spacing.tabBand)
        .accessibilityHidden(true)
    }
}
