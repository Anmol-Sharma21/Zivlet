import AppKit
import Testing
import ZivletCore

/// A tool petal's label sits in an 82 × 22 pt frame at 7.5 pt semibold with 0.2 pt tracking, two lines at most
/// (03a §2.2, `PetalLabel`). LOCK · UNLOCK is the longest label so far (plan 20f E1), and it must fit on one line.
@Suite("Tool labels fit their petal (03a §2.2)")
struct ToolLabelFitTests {
    static let frame = CGSize(width: 82, height: 22)
    static let fontSize: CGFloat = 7.5
    static let tracking: CGFloat = 0.2

    /// The width and height the label takes on one line, as `PetalLabel` draws it.
    static func size(of label: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let text = NSAttributedString(string: label, attributes: [.font: font, .kern: tracking])
        return text.size()
    }

    @Test func lockUnlockFitsOnOneLine() {
        let size = Self.size(of: "LOCK · UNLOCK")
        #expect(size.width <= Self.frame.width, "\(size.width) pt wide")
        #expect(size.height <= Self.frame.height, "\(size.height) pt high")
    }

    @Test(arguments: ToolCatalog.standard.specs.map(\.wheelLabel))
    func everyToolLabelFitsOnOneLine(label: String) {
        #expect(Self.size(of: label).width <= Self.frame.width, "\(label)")
    }
}
