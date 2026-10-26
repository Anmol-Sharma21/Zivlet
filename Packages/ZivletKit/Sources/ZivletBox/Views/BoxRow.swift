import SwiftUI
import ZivletNotch

/// One list row (19c §3.2): a 24 pt icon, the name in the primary style giving way in the middle, the size right in
/// the secondary style. Where the item lives is spoken, not shown.
struct BoxRow: View {
    static let nameTruncation = Text.TruncationMode.middle

    let item: BoxItemModel
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    private var isSelected: Bool { model.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            BoxThumb(item: item, image: model.images[item.id], side: BoxLook.List.icon, radius: BoxLook.List.iconRadius)
            Text(item.name)
                .font(IslandContentLook.TypeStyle.primary)
                .foregroundStyle(IslandInk.primary)
                .lineLimit(1)
                .truncationMode(Self.nameTruncation)
                .opacity(item.isAvailable ? 1 : BoxLook.missingOpacity)
            Spacer(minLength: IslandContentLook.Spacing.s)
            if let bytes = item.bytes {
                Text(BoxCopy.size(bytes))
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, IslandContentLook.Spacing.s)
        .frame(height: BoxLook.List.rowHeight)
        .background(BoxSelectionFill(isSelected: isSelected))
        .overlay { BoxItemDrag(item: item, model: model, press: press) }
        .modifier(BoxContextMenu(press: press))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The list: one 36 pt row per item, no dividers.
struct BoxList: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.items) { BoxRow(item: $0, model: model, press: press) }
        }
    }
}
