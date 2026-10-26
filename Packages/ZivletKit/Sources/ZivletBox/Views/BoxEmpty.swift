import SwiftUI
import ZivletNotch

/// Empty (19c §4.1): the empty tray at 28 pt, white 0.6, over "Drop files here".
struct BoxEmpty: View {
    var body: some View {
        VStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: BoxSymbols.empty)
                .font(BoxLook.Empty.symbol)
                .foregroundStyle(Color.white.opacity(BoxLook.Empty.symbolOpacity))
            Text(BoxCopy.empty)
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(IslandInk.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Drop target (19c D-BL7): the content behind dims to 0.4 (done by the card); the drop symbol over "Add 3".
struct BoxDropOverlay: View {
    let count: Int
    var showsLine = true

    var body: some View {
        VStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: BoxSymbols.dropHere)
                .font(IslandContentLook.Symbol.toast)
                .foregroundStyle(IslandInk.primary)
            if showsLine {
                Text(BoxCopy.add(count))
                    .font(IslandContentLook.TypeStyle.primary)
                    .foregroundStyle(IslandInk.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoxSpeech.dropTarget(count))
    }
}
