import SwiftUI
import ZivletNotchCore

/// The collapsed island's tab (design/19 §3.4, §4.3): the source file's icon left, "3 jobs" in the middle, the ring,
/// stepped glyph, check mark or error glyph right. It reads the board as last published, which changes only when
/// the board says `redraw` or the layout changes (D-N7). The island group speaks for it, so it is hidden from
/// VoiceOver itself.
struct NotchTab: View {
    static let sidePadding: CGFloat = 8

    let model: NotchHUDModel
    let display: UInt32

    var body: some View {
        HStack(spacing: 6) {
            if let tab = model.board.tab(on: display) {
                NotchIcon(icon: tab.icon)
                Spacer(minLength: 0)
                if let count = tab.count {
                    Text(count).font(.caption.weight(.semibold)).foregroundStyle(NotchInk.primary).lineLimit(1)
                }
                Spacer(minLength: 0)
                NotchStatusGlyph(tab: tab)
            }
        }
        .padding(.horizontal, Self.sidePadding)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.Metrics.tabHeight)
        .accessibilityHidden(true)
    }
}
