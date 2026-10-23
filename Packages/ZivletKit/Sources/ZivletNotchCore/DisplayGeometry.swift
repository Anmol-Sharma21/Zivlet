import Foundation
import ZivletCore

/// One display as the island sees it (design/19 §3.2): all values in global points, AppKit orientation. The values
/// come from AppKit, so the initializer and the decoder refuse non-finite numbers and negative sizes.
public struct DisplayGeometry: Sendable, Equatable, Codable {
    /// Why a set of display values was refused; `field` names the value, never a path or a name.
    public enum Invalid: Error, Equatable, CustomStringConvertible {
        case notFinite(field: String)
        case negative(field: String)

        public var description: String {
            switch self {
            case .notFinite(let field): "Display value \(field) is not a finite number"
            case .negative(let field): "Display value \(field) is negative"
            }
        }
    }

    /// `CGDirectDisplayID`.
    public let id: UInt32
    public let frame: Rect2D
    public let visibleFrame: Rect2D
    public let safeAreaTop: Double
    public let auxiliaryTopLeft: Rect2D?
    public let auxiliaryTopRight: Rect2D?
    /// `CGDisplayIsBuiltin`.
    public let isBuiltIn: Bool

    public init(
        id: UInt32, frame: Rect2D, visibleFrame: Rect2D, safeAreaTop: Double, auxiliaryTopLeft: Rect2D?,
        auxiliaryTopRight: Rect2D?, isBuiltIn: Bool
    ) throws {
        try Self.check(frame, "frame")
        try Self.check(visibleFrame, "visibleFrame")
        try Self.check(safeAreaTop, "safeAreaTop", mayBeNegative: false)
        if let auxiliaryTopLeft { try Self.check(auxiliaryTopLeft, "auxiliaryTopLeft") }
        if let auxiliaryTopRight { try Self.check(auxiliaryTopRight, "auxiliaryTopRight") }
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, frame, visibleFrame, safeAreaTop, auxiliaryTopLeft, auxiliaryTopRight, isBuiltIn
    }

    /// Recorded fixtures are decoded through the same checks as live values.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: try c.decode(UInt32.self, forKey: .id), frame: try c.decode(Rect2D.self, forKey: .frame),
            visibleFrame: try c.decode(Rect2D.self, forKey: .visibleFrame),
            safeAreaTop: try c.decode(Double.self, forKey: .safeAreaTop),
            auxiliaryTopLeft: try c.decodeIfPresent(Rect2D.self, forKey: .auxiliaryTopLeft),
            auxiliaryTopRight: try c.decodeIfPresent(Rect2D.self, forKey: .auxiliaryTopRight),
            isBuiltIn: try c.decode(Bool.self, forKey: .isBuiltIn))
    }

    private static func check(_ rect: Rect2D, _ name: String) throws {
        try check(rect.x, "\(name).x", mayBeNegative: true)
        try check(rect.y, "\(name).y", mayBeNegative: true)
        try check(rect.width, "\(name).width", mayBeNegative: false)
        try check(rect.height, "\(name).height", mayBeNegative: false)
    }

    private static func check(_ value: Double, _ name: String, mayBeNegative: Bool) throws {
        guard value.isFinite else { throw Invalid.notFinite(field: name) }
        guard mayBeNegative || value >= 0 else { throw Invalid.negative(field: name) }
    }
}

// Copy Diagnostics (design/19 §3.3, Q15): every value of a display on one line, so other Macs' notch sizes can be
// recorded as fixtures. Numbers and the housing only; no display names.
extension DisplayGeometry {
    public var diagnosticsLine: String {
        let parts = [
            "display \(id): frame \(Self.text(frame))", "visible \(Self.text(visibleFrame))",
            "safe top \(Self.text(safeAreaTop))", "aux left \(Self.text(auxiliaryTopLeft))",
            "aux right \(Self.text(auxiliaryTopRight))", "housing \(Self.text(NotchGeometry.housing(of: self)))",
        ]
        return (parts + (isBuiltIn ? ["built in"] : [])).joined(separator: " · ")
    }

    private static func text(_ rect: Rect2D?) -> String {
        guard let rect else { return "none" }
        return [rect.x, rect.y, rect.width, rect.height].map(text).joined(separator: " ")
    }

    /// Whole points without a fraction, others as Swift prints them.
    private static func text(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(value)
    }
}
