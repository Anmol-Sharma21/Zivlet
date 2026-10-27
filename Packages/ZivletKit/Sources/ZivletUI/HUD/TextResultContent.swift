import SwiftUI
import ZivletActions

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

/// What both presenters draw for a text result: up to three preview lines, the count line, and the buttons; when ⌥
/// already wrote the `.txt` files, a line says so and Save as Text is not offered again.
struct TextResultModel: Equatable {
    let lines: [String]
    let countLine: String
    let savedLine: String?
    let buttons: [TextResultButton]

    init(_ outcome: TextOutcome) {
        lines = outcome.preview
        countLine = outcome.countLine
        switch outcome.savedFiles.count {
        case 0: savedLine = nil
        case 1: savedLine = "Saved " + (outcome.savedFiles.first?.lastPathComponent ?? "")
        default: savedLine = "Saved \(outcome.savedFiles.count) text files"
        }
        buttons = outcome.savedFiles.isEmpty ? [.copyAgain, .saveText, .showAll] : [.copyAgain, .showAll]
    }
}

/// The text result on the HUD's glass (OWN-UI-1, few words): "Text copied", the preview lines in the secondary ink,
/// the count line, and three icon buttons.
struct TextResultContent: View {
    /// NFR-14: the secondary ink, 4.5:1 over the worst backdrop in both schemes.
    static let lineOpacity = HUDInk.secondaryOpacity

    let toast: String
    let model: TextResultModel
    let press: (TextResultButton) -> Void

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
                }
                Spacer(minLength: 0)
                ForEach(model.buttons, id: \.self) { button in
                    Button {
                        press(button)
                    } label: {
                        Label(button.title, systemImage: button.symbol).labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help(button.title)
                    .accessibilityLabel(button.accessibilityLabel)
                }
            }
        }
    }
}
