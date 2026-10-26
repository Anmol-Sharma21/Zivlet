import SwiftUI

/// Why an item cannot be used, by shape (19c D-BL8): the symbol in a small dark circle that reads over any thumbnail.
struct BoxBadge: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .font(BoxLook.Badge.symbol)
            .foregroundStyle(.white)
            .frame(width: BoxLook.Badge.glyph, height: BoxLook.Badge.glyph)
            .frame(width: BoxLook.Badge.circle, height: BoxLook.Badge.circle)
            .background(Circle().fill(Color.black.opacity(BoxLook.Badge.circleOpacity)))
            .accessibilityHidden(true)
    }
}

/// An item's picture: its thumbnail or type icon, or a plain document symbol before the controller has one; dimmed
/// when the item cannot be used, with its badge at the bottom right. A thumbnail that replaces the icon fades in over
/// 0.12 s (D-BL11), at once under Reduce Motion.
struct BoxThumb: View {
    let item: BoxItemModel
    let image: NSImage?
    let side: CGFloat
    let radius: CGFloat
    var fades = true

    private var imageID: ObjectIdentifier? { image.map(ObjectIdentifier.init) }

    var body: some View {
        ZStack {
            picture
                .id(imageID)
                .transition(.opacity)
        }
        .animation(fades ? .easeOut(duration: BoxLook.Motion.thumbnailFade) : nil, value: imageID)
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(item.isAvailable ? 1 : BoxLook.missingOpacity)
        .overlay(alignment: .bottomTrailing) {
            if let badge = item.badge { BoxBadge(symbol: badge).offset(x: 4, y: 4) }
        }
    }

    @ViewBuilder private var picture: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc").font(.system(size: side * 0.5)).foregroundStyle(.white.opacity(0.8))
        }
    }
}
