import AppKit
import SwiftUI
import ZivletActions
import ZivletNotch
import ZivletRuntime

/// The island's result card (19b §5, F1, F3): a 40 pt thumbnail (a drag source for every output), "Saved photo.jpg"
/// over "2.1 MB → 640 KB", notes and the undo reply as captions, the details box, and the model's buttons as icons,
/// on the second line when they fit beside it, else on a row of their own.
struct NotchResultCard: View {
    static let thumbnailSide: CGFloat = 40
    /// Room left over when the buttons go beside the second line, for rounding between AppKit's measure and SwiftUI's.
    static let fitMargin: CGFloat = 2
    static var thumbnailRadius: CGFloat { IslandLook.Radius.inner }

    let model: ResultCardModel
    let state: CardState
    let width: CGFloat
    var onDrag: (Bool) -> Void = { _ in }
    let act: (ResultCardModel.Button) -> Void

    var body: some View {
        let lines = Self.lines(model)
        let beside = Self.buttonsFitBeside(
            lines.secondary, buttons: state.visible(model).count, thumbnail: !state.remaining(model.outputs).isEmpty,
            width: width)
        VStack(alignment: .leading, spacing: NotchLook.Spacing.s) {
            HStack(alignment: .center, spacing: NotchLook.Spacing.m) {
                if let first = state.remaining(model.outputs).first { thumbnail(first) }
                VStack(alignment: .leading, spacing: NotchLook.Spacing.xs) {
                    Text(lines.primary).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: NotchLook.Spacing.s) {
                        secondary(lines.secondary)
                        Spacer(minLength: 0)
                        if beside { buttons }
                    }
                    captions
                }
            }
            if !beside {
                HStack {
                    Spacer(minLength: 0)
                    buttons
                }
            }
            if state.showsDetails, let details = model.details { NotchDetailsBox(details: details) }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The name once: "Saved photo.jpg" and "2.1 MB → 640 KB". Several files or a partial result keep the model's
    /// title, which says so; without a saved file, the title and subtitle.
    static func lines(_ model: ResultCardModel) -> (primary: String, secondary: String) {
        guard let line = model.sizeLine, let split = line.range(of: " · ", options: .backwards) else {
            return (model.title, model.subtitle)
        }
        let label = line[..<split.lowerBound]
        let primary = model.outputs.count == 1 && model.phase == .succeeded ? "Saved \(label)" : model.title
        return (primary, String(line[split.upperBound...]))
    }

    /// The presses on screen now, in the model's order.
    static func presses(_ model: ResultCardModel, state: CardState) -> [NotchHUD.Press] {
        state.visible(model).map(NotchHUD.Press.init)
    }

    @ViewBuilder private var captions: some View {
        ForEach(model.notes, id: \.self) { NotchCaption(text: $0) }
        if let message = state.undoMessage { NotchCaption(text: message) }
    }

    private func secondary(_ text: String) -> some View {
        Text(text).font(NotchLook.TypeStyle.secondary).foregroundStyle(NotchInk.secondary).lineLimit(2)
            .truncationMode(.middle)
    }

    private var buttons: some View {
        HStack(spacing: NotchLook.Spacing.xs) {
            ForEach(state.visible(model), id: \.self) { button in
                NotchIconButton(press: NotchHUD.Press(button)) { act(button) }
                    .keyboardShortcut(NotchButtonRow.shortcut(NotchHUD.Press(button)))
            }
        }
    }

    /// The buttons go beside the second line when it, measured in the font it is drawn in, and they fit in the text
    /// column with `fitMargin` to spare.
    static func buttonsFitBeside(_ secondary: String, buttons count: Int, thumbnail: Bool, width: CGFloat) -> Bool {
        let side = CGFloat(count)
        let buttons = side * NotchLook.Symbol.buttonSide + max(0, side - 1) * NotchLook.Spacing.xs
        let column = width - (thumbnail ? thumbnailSide + NotchLook.Spacing.m : 0)
        return textWidth(of: secondary) + NotchLook.Spacing.s + buttons + fitMargin <= column
    }

    /// The width of `text` on one line in the second line's font (tabular digits).
    static func textWidth(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NotchLook.TypeStyle.secondaryFont]).width.rounded(.up)
    }

    private func thumbnail(_ url: URL) -> some View {
        let image = state.thumbnail ?? ThumbnailLoader.placeholder(for: url)
        return FileDragSource(urls: state.remaining(model.outputs), image: image, onDrag: onDrag)
            .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
            .clipShape(.rect(cornerRadius: Self.thumbnailRadius, style: .continuous))
            .accessibilityLabel("Result file. Drag it to use it elsewhere.")
    }
}

/// The technical detail (an exit status and the helper's last lines), selectable for a bug report, in a box with the
/// card's inner radius.
struct NotchDetailsBox: View {
    let details: String

    var body: some View {
        ScrollView {
            Text(details).font(NotchLook.TypeStyle.caption.monospaced()).foregroundStyle(NotchInk.secondary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .fixedSize(horizontal: false, vertical: true)
        .padding(NotchLook.Spacing.s)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: IslandLook.Radius.inner, style: .continuous))
    }
}

/// A caption under a card's lines: notes, the undo reply, a detail, "+2 more" (19b D-NL7).
struct NotchCaption: View {
    let text: String

    var body: some View {
        Text(text).font(NotchLook.TypeStyle.caption).foregroundStyle(NotchInk.secondary).lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
