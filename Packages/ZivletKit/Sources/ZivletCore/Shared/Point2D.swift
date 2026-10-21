/// Plain point in points, AppKit orientation (y up). Keeps pure modules free of CoreGraphics.
public struct Point2D: Sendable, Hashable, Codable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = Point2D(x: 0, y: 0)
}
