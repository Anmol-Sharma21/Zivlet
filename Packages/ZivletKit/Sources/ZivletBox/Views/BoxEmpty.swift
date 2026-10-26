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
    static let backingOpacity = 0.55

    let count: Int

    var body: some View {
        VStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: BoxSymbols.dropHere)
                .font(IslandContentLook.Symbol.toast)
                .foregroundStyle(IslandInk.primary)
            Text(BoxCopy.add(count))
                .font(IslandContentLook.TypeStyle.primary)
                .foregroundStyle(IslandInk.primary)
        }
        .padding(.horizontal, IslandContentLook.Spacing.m)
        .padding(.vertical, IslandContentLook.Spacing.s)
        // A dark fill (no border) keeps the line readable over the dimmed items behind it.
        .background(
            RoundedRectangle(cornerRadius: IslandLook.Radius.inner, style: .continuous)
                .fill(Color.black.opacity(Self.backingOpacity))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BoxSpeech.dropTarget(count))
    }
}
