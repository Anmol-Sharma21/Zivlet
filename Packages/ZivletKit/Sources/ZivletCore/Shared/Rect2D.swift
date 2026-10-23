import CoreGraphics
import Foundation

/// Axis-aligned rectangle in global points, AppKit orientation (origin bottom-left). Pure modules use it instead of
/// `CGRect`; the bridge below is for the AppKit shells. It imports CoreGraphics so its `CGRect` is the one the shells
/// see: through Foundation alone the Release build could not read the bridge back in other modules.
public struct Rect2D: Sendable, Hashable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Half-open on the max edges, so a point on the seam between two displays belongs to one of them.
    public func contains(_ p: Point2D) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}

extension Rect2D {
    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var cgRect: CGRect { CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height)) }
}
