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
                item: item, image: model.images[item.id], side: BoxLook.Grid.thumb, radius: BoxLook.Grid.thumbRadius,
                fades: !model.reduceMotion)
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
        .modifier(BoxItemAccessibility(item: item, isSelected: isSelected, press: press))
        .id(item.id)
    }
}

/// One item for VoiceOver (19c §6): its spoken line, selected or not, and actions, since the mouse handling that
/// selects is hidden inside the element: press toggles the item in the selection, and Quick Look, Remove from Box
/// and (for a missing item) Locate… act on it alone. Its coming on screen and leaving drive the thumbnails.
struct BoxItemAccessibility: ViewModifier {
    let item: BoxItemModel
    let isSelected: Bool
    let press: (BoxPress) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.spoken)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { press(.select(item.id, extend: false, toggle: true)) }
            .accessibilityAction(named: BoxCopy.title(.quickLook)) { alone(.quickLook) }
            .accessibilityAction(named: BoxCopy.title(.remove)) { alone(.remove) }
            .accessibilityActions {
                if !item.isAvailable { Button(BoxCopy.title(.locate)) { alone(.locate) } }
            }
            .onAppear { press(.shown(item.id, true)) }
            .onDisappear { press(.shown(item.id, false)) }
    }

    /// Selects only this item, then runs `command` on it.
    private func alone(_ command: BoxPress) {
        press(.select(item.id, extend: false, toggle: false))
        press(command)
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

    /// The payload is worked out when a drag starts, never in the body: with every item selected, building it for
    /// each visible cell on each render cost tens of milliseconds.
    var body: some View {
        FileDragSource(
            provide: { [model, item] in
                model.selection.contains(item.id) ? model.dragURLs : (item.url.map { [$0] } ?? [])
            }, image: model.images[item.id] ?? NSImage(), drawsImage: false,
            onEnded: { [model, item, press] operation in
                Self.ended(operation, ids: model.dragIDs(from: item)).map(press)
            },
            onClick: { flags in
                press(.select(item.id, extend: flags.contains(.shift), toggle: flags.contains(.command)))
            })
    }

    /// A drag that something took (copy, link or generic) left the box; one that nobody took did not.
    static func ended(_ operation: NSDragOperation, ids: [UUID]) -> BoxPress? {
        operation.isEmpty || ids.isEmpty ? nil : .draggedOut(ids)
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
