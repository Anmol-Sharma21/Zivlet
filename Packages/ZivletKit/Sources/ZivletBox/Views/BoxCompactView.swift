import SwiftUI
import ZivletActions
import ZivletNotch

/// The tray's expanded content (19c §4.3, plan 16e D11): the header with Share and Open Drop Box, then a strip of up
/// to six 40 pt thumbnails, the last one "+6" when there are more. Thumbnails drag their item, the strip's empty
/// space drags every item, "+6" opens the panel; `drag` hears a drag begin and end, so the island is held meanwhile
/// (D-N13). No surface of its own: the island draws the finish around it.
public struct BoxCompactView: View {
    public static var height: CGFloat {
        2 * IslandContentLook.Spacing.l + BoxLook.Panel.headerHeight + IslandContentLook.Spacing.s + BoxLook.Tray.thumb
    }

    let model: BoxViewModel
    let press: (BoxPress) -> Void
    let drag: (Bool) -> Void

    public init(model: BoxViewModel, press: @escaping (BoxPress) -> Void, drag: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.press = press
        self.drag = drag
    }

    /// The thumbnails shown: all up to six, else five and the "+N" tile.
    static func strip(_ items: [BoxItemModel]) -> [BoxItemModel] {
        items.count <= BoxLook.Tray.maxThumbs ? items : Array(items.prefix(BoxLook.Tray.maxThumbs - 1))
    }

    /// The number on the last tile; 0 when every item fits.
    static func overflow(_ count: Int) -> Int {
        count <= BoxLook.Tray.maxThumbs ? 0 : count - BoxLook.Tray.maxThumbs + 1
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.s) {
            header
            HStack(spacing: IslandContentLook.Spacing.s) {
                ForEach(Self.strip(model.items)) { item in
                    BoxThumb(
                        item: item, image: model.images[item.id], side: BoxLook.Tray.thumb,
                        radius: BoxLook.Tray.thumbRadius, fades: !model.reduceMotion
                    )
                    .overlay {
                        FileDragSource(
                            urls: item.url.map { [$0] } ?? [], image: model.images[item.id] ?? NSImage(),
                            drawsImage: false, onDrag: drag,
                            onEnded: { operation in
                                BoxItemDrag.ended(operation, ids: item.url == nil ? [] : [item.id]).map(press)
                            })
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.spoken)
                }
                if Self.overflow(model.items.count) > 0 { more }
                Spacer(minLength: 0)
            }
            .background { everything }
        }
        .padding(IslandContentLook.Spacing.l)
        .frame(width: BoxLook.Tray.compactWidth, height: Self.height, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: BoxSymbols.box).font(IslandContentLook.Symbol.tab).foregroundStyle(IslandInk.primary)
            Text(BoxCopy.items(model.items.count))
                .font(IslandContentLook.TypeStyle.primary).foregroundStyle(IslandInk.primary)
            Text(model.secondaryLine)
                .font(IslandContentLook.TypeStyle.secondary).foregroundStyle(IslandInk.secondary)
            Spacer(minLength: 0)
            BoxIconButton(press: .share, action: press)
            BoxIconButton(press: .openPanel, action: press)
        }
        .frame(height: BoxLook.Panel.headerHeight)
    }

    /// The strip's empty space: a drag from it carries every present item.
    private var everything: some View {
        FileDragSource(
            provide: { [model] in model.dragURLs }, image: NSImage(), drawsImage: false, onDrag: drag,
            onEnded: { [model, press] operation in
                BoxItemDrag.ended(operation, ids: model.items.filter { $0.url != nil }.map(\.id)).map(press)
            })
    }

    private var more: some View {
        Button {
            press(.openPanel)
        } label: {
            Text("+\(Self.overflow(model.items.count))")
                .font(IslandContentLook.TypeStyle.primary)
                .foregroundStyle(IslandInk.primary)
                .frame(width: BoxLook.Tray.thumb, height: BoxLook.Tray.thumb)
        }
        .buttonStyle(BoxTileButtonStyle())
        .help(BoxCopy.title(.openPanel))
        .accessibilityLabel(BoxCopy.title(.openPanel))
    }
}

/// The "+6" tile: the resting fill of a selected cell, lighter on hover and pressed, the island's icon-button values
/// (19b D-NL9) on the tile's rounded rectangle.
struct BoxTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BoxTile(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct BoxTile<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @State private var hovering = false

    var body: some View {
        label
            .background(
                RoundedRectangle(cornerRadius: BoxLook.Tray.thumbRadius, style: .continuous)
                    .fill(Color.white.opacity(fill))
            )
            .contentShape(RoundedRectangle(cornerRadius: BoxLook.Tray.thumbRadius, style: .continuous))
            .onHover { hovering = $0 }
    }

    private var fill: Double {
        isPressed ? BoxLook.Tile.pressed : hovering ? BoxLook.Tile.hover : BoxLook.Selection.fill
    }
}
