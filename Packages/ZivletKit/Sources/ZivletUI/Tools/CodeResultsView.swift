import AppKit
import SwiftUI
import ZivletActions
import ZivletNotch

/// A row's buttons.
public enum CodeButton: Sendable { case copy, open }

/// Read QR's results in the tool window (P2-51, plan 20b A9, D-M7-13): Copy per row, Copy All as Apply, and Open for
/// a web link, which runs only when it is pressed. Copying writes the general pasteboard for this Mac only (the person
/// asked to copy); opening goes through the injected `open`, `NSWorkspace` in the app.
public final class CodeResultsContent: WindowToolContent {
    public let results: CodeResultsModel
    public var model: ToolWindowModel { results.window }
    public var modelChanged: (ToolWindowModel) -> Void = { _ in }
    private let clipboard: ClipboardAction
    private let open: (URL) -> Void

    public init(
        model: CodeResultsModel, clipboard: ClipboardAction = ClipboardAction(),
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        results = model
        self.clipboard = clipboard
        self.open = open
    }

    public var view: AnyView {
        AnyView(CodeResultsView(results: results) { [weak self] button, row in self?.press(button, row: row) })
    }

    public func press(_ button: CodeButton, row index: Int) {
        guard results.rows.indices.contains(index) else { return }
        let row = results.rows[index]
        switch button {
        case .copy: _ = clipboard.copyText(row.payload)
        case .open: if let link = row.link { open(link) }
        }
    }

    /// Copy All, then the window closes.
    public func apply() -> Bool {
        _ = clipboard.copyText(results.copyAllText)
        return true
    }

    public func cancel() {}
}

/// The rows (headed by their file's name when they came from several files), then the notes for files not read.
/// Payloads are shown in full, wrapped and selectable; a long list scrolls.
struct CodeResultsView: View {
    static let maximumHeight: CGFloat = 320

    let results: CodeResultsModel
    let press: (CodeButton, Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IslandContentLook.Spacing.m) {
                ForEach(results.rows) { row in
                    if results.groupsByFile, row.id == 0 || results.rows[row.id - 1].fileName != row.fileName {
                        Text(row.fileName)
                            .font(IslandContentLook.TypeStyle.secondary)
                            .foregroundStyle(IslandInk.secondary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    CodeRowView(row: row, press: press)
                }
                ForEach(results.notes, id: \.self) { note in
                    Label(note, systemImage: ToolWindowView.reasonSymbol)
                        .font(IslandContentLook.TypeStyle.secondary)
                        .foregroundStyle(IslandInk.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: Self.maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Open's VoiceOver hint: what it does and the whole link.
    static func openHint(_ row: CodeRow) -> String {
        "\(CodeCopy.openHint): \(row.link?.absoluteString ?? row.payload)"
    }
}

/// One code: its payload and caption, Copy, and Open for a web link.
struct CodeRowView: View {
    let row: CodeRow
    let press: (CodeButton, Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: IslandContentLook.Spacing.s) {
            VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
                Text(row.payload)
                    .font(IslandContentLook.TypeStyle.primary)
                    .foregroundStyle(IslandInk.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = row.caption {
                    Text(caption)
                        .font(IslandContentLook.TypeStyle.secondary)
                        .foregroundStyle(IslandInk.secondary)
                }
            }
            Spacer(minLength: 0)
            CodeIconButton(symbol: "doc.on.doc", title: "Copy") { press(.copy, row.id) }
            if row.link != nil {
                CodeIconButton(symbol: "arrow.up.right.square", title: "Open", hint: CodeResultsView.openHint(row)) {
                    press(.open, row.id)
                }
            }
        }
    }
}

/// An SF Symbol in the island's 28 pt round hit area, with its word as tooltip and VoiceOver label.
struct CodeIconButton: View {
    let symbol: String
    let title: String
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(IslandContentLook.Symbol.button)
                .foregroundStyle(IslandInk.primary)
                .frame(width: IslandContentLook.Symbol.buttonSide, height: IslandContentLook.Symbol.buttonSide)
                .contentShape(Circle())
        }
        .buttonStyle(IslandIconButtonStyle())
        .help(hint ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
    }
}
