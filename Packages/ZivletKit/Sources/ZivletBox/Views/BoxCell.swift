import SwiftUI
import ZivletActions

/// One grid cell (19c §3.2): the 48 pt thumbnail over one white 11 pt line that gives way in the middle; a white
/// 0.14 fill when selected. The cell carries its drag: the selection when it is selected, else the item.
struct BoxCell: View {
    static let nameTruncation = Text.TruncationMode.middle

    let item: BoxItemModel
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    private var isSelected: Bool { model.selection.contains(item.id) }

    var body: some View {
        VStack(spacing: BoxLook.Grid.nameGap) {
            BoxThumb(
                item: item, image: model.images[item.id], side: BoxLook.Grid.thumb, radius: BoxLook.Grid.thumbRadius)
            Text(item.name)
                .font(BoxLook.Grid.nameFont)
                .foregroundStyle(Color.white.opacity(BoxLook.Grid.nameOpacity))
                .lineLimit(1)
                .truncationMode(Self.nameTruncation)
                .opacity(item.isAvailable ? 1 : BoxLook.missingOpacity)
                .frame(width: BoxLook.Grid.cell, height: BoxLook.Grid.nameHeight)
        }
        .frame(width: BoxLook.Grid.cell, height: BoxLook.Grid.rowHeight)
        .background(BoxSelectionFill(isSelected: isSelected))
        .overlay { BoxItemDrag(item: item, model: model, press: press) }
        .modifier(BoxContextMenu(press: press))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The white 0.14 rounded fill behind a selected cell or row (19c D-BL6).
struct BoxSelectionFill: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: BoxLook.Selection.radius, style: .continuous)
            .fill(Color.white.opacity(isSelected ? BoxLook.Selection.fill : 0))
    }
}

/// Clicks select (⇧ extends, ⌘ toggles); a drag carries the selection or the item, as the shared drag source does.
struct BoxItemDrag: View {
    let item: BoxItemModel
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    var body: some View {
        let urls = model.selection.contains(item.id) ? model.dragURLs : (item.url.map { [$0] } ?? [])
        FileDragSource(
            urls: urls, image: model.images[item.id] ?? NSImage(), drawsImage: false,
            onClick: { flags in
                press(.select(item.id, extend: flags.contains(.shift), toggle: flags.contains(.command)))
            })
    }
}

/// The context menu (17e §2.3): the bar's and the overflow's commands, acting on the selection or every item.
struct BoxContextMenu: ViewModifier {
    let press: (BoxPress) -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            ForEach(BoxPress.bar + BoxPress.overflow, id: \.self.menuID) { item in
                Button(BoxCopy.title(item)) { press(item) }
            }
        }
    }
}
