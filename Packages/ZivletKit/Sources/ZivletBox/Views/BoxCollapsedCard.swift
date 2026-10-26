import SwiftUI
import ZivletActions
import ZivletNotch

/// Collapsed (19c §4.1): a short card with up to three thumbnails fanned 6 pt apart, which drag every item out, the
/// count over the size, and the button that opens the full panel.
struct BoxCollapsedCard: View {
    static let fan: CGFloat = 6
    static let fanCount = 3

    let model: BoxViewModel
    let press: (BoxPress) -> Void

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.m) {
            stack
            VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
                Text(BoxCopy.items(model.items.count))
                    .font(IslandContentLook.TypeStyle.primary)
                    .foregroundStyle(IslandInk.primary)
                Text(model.secondaryLine)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
            }
            Spacer(minLength: 0)
            BoxIconButton(press: .openPanel, action: press)
        }
        .padding(.horizontal, IslandContentLook.Spacing.l)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BoxSpeech.header(count: model.items.count, bytes: model.totalBytes))
    }

    private var stack: some View {
        let shown = Array(model.items.prefix(Self.fanCount))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { offset, item in
                BoxThumb(
                    item: item, image: model.images[item.id], side: BoxLook.Grid.thumb,
                    radius: BoxLook.Grid.thumbRadius
                )
                .offset(x: CGFloat(offset) * Self.fan, y: CGFloat(offset) * Self.fan)
            }
        }
        .frame(
            width: BoxLook.Grid.thumb + CGFloat(Self.fanCount - 1) * Self.fan,
            height: BoxLook.Grid.thumb + CGFloat(Self.fanCount - 1) * Self.fan, alignment: .topLeading
        )
        .overlay {
            FileDragSource(
                urls: model.items.compactMap(\.url), image: shown.first.flatMap { model.images[$0.id] } ?? NSImage(),
                drawsImage: false)
        }
    }
}
