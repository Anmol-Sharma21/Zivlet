/// One piece of a one-line text: a piece that gives way truncates in its middle before the others shorten, so a long
/// file name loses its middle, not the sizes, the percent or the reason beside it.
public struct LinePart: Sendable, Equatable {
    public let text: String
    public let givesWay: Bool

    public init(text: String, givesWay: Bool) {
        self.text = text
        self.givesWay = givesWay
    }

    public static func joined(_ parts: [LinePart]) -> String { parts.map(\.text).joined() }
}
