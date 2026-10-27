import SwiftUI
import ZivletActions
import ZivletNotch

/// The text card's three buttons (P2-104, plan 18d D11): SF Symbols with a tooltip and an accessibility label.
public enum TextResultButton: Sendable, Hashable, CaseIterable {
    case copyAgain, saveText, showAll

    public var title: String {
        switch self {
        case .copyAgain: "Copy Again"
        case .saveText: "Save as Text"
        case .showAll: "Show All"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .copyAgain: "Copy again"
        case .saveText: "Save as text"
        case .showAll: "Show all text"
        }
    }

    public var symbol: String {
        switch self {
        case .copyAgain: "doc.on.doc"
        case .saveText: "square.and.arrow.down"
        case .showAll: "text.alignleft"
        }
    }
}

/// What both presenters draw for a text result: up to three preview lines, the count line, any notes, and the
/// buttons; when ⌥ already wrote the `.txt` files, a line says so and Save as Text is not offered again.
struct TextResultModel: Equatable {
    let lines: [String]
    let countLine: String
    let savedLine: String?
    let notes: [String]
    let buttons: [TextResultButton]

    init(_ outcome: TextOutcome) {
        lines = outcome.preview
        countLine = outcome.countLine
        notes = outcome.notes
        switch outcome.savedFiles.count {
        case 0: savedLine = nil
        case 1: savedLine = "Saved " + (outcome.savedFiles.first?.lastPathComponent ?? "")
        default: savedLine = "Saved \(outcome.savedFiles.count) text files"
        }
        buttons = outcome.savedFiles.isEmpty ? [.copyAgain, .saveText, .showAll] : [.copyAgain, .showAll]
    }
}

/// The text result on the HUD's glass (OWN-UI-1, few words): "Text copied", the preview lines in the secondary ink,
/// the count line and notes, the three icon buttons and Close (Escape once the panel is key, as every HUD card has),
/// each in the island's 28 pt round hit area (19b D-NL9).
struct TextResultContent: View {
    /// NFR-14: the secondary ink, 4.5:1 over the worst backdrop in both schemes.
    static let lineOpacity = HUDInk.secondaryOpacity
    static let buttonSide = NotchLook.Symbol.buttonSide
    static let closeSymbol = "xmark.circle"

    let toast: String
    let model: TextResultModel
    let press: (TextResultButton) -> Void
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(toast).font(.headline).lineLimit(1)
            ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.callout).foregroundStyle(HUDInk.secondary).lineLimit(1).truncationMode(.tail)
            }
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.countLine).font(.caption).foregroundStyle(HUDInk.secondary).lineLimit(1)
                    if let saved = model.savedLine {
                        Text(saved).font(.caption).foregroundStyle(HUDInk.secondary).lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ForEach(Array(model.notes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.caption).foregroundStyle(HUDInk.secondary).lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                ForEach(model.buttons, id: \.self) { button in
                    iconButton(button.symbol, title: button.title, label: button.accessibilityLabel) { press(button) }
                }
                iconButton(Self.closeSymbol, title: "Close", label: "Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func iconButton(_ symbol: String, title: String, label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Self.buttonSide, height: Self.buttonSide)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(label)
    }
}
