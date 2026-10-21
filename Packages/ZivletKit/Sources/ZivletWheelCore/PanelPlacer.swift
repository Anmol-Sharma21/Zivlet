import ZivletCore

/// Axis-aligned rectangle in global points, AppKit orientation (origin bottom-left). Keeps WheelCore free of CoreGraphics.
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

/// One display as the placer sees it: full frame and the frame minus menu bar and Dock.
public struct ScreenFrame: Sendable, Equatable {
    public let frame: Rect2D
    public let visibleFrame: Rect2D

    public init(frame: Rect2D, visibleFrame: Rect2D) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct PanelPlacement: Sendable, Equatable {
    public let screenIndex: Int
    /// Wheel centre in global points; equals the pointer unless the disk had to move inside the visible frame.
    public let wheelCentre: Point2D
    /// The 372 pt panel centred on `wheelCentre`. It may overhang the screen; only the disk is kept inside.
    public let panelFrame: Rect2D
    /// `wheelCentre − pointer`; zero away from screen edges.
    public let offset: Point2D
}

/// Pure placement (03a §2.1, 01-prd FR-24 P1): centre on the pointer, shift only so the disk (r 125.92) plus an 8 pt
/// margin stays inside the screen's `visibleFrame`.
public struct PanelPlacer: Sendable {
    public let geometry: WheelGeometry
    public let margin: Double

    public init(geometry: WheelGeometry = .standard, margin: Double = 8) {
        self.geometry = geometry
        self.margin = margin
    }

    /// The screen containing the pointer, else the first screen (the menu-bar screen). Nil when there are no screens.
    public func place(pointer: Point2D, screens: [ScreenFrame]) -> PanelPlacement? {
        guard !screens.isEmpty else { return nil }
        let index = screens.firstIndex { $0.frame.contains(pointer) } ?? 0
        let visible = screens[index].visibleFrame
        let reach = geometry.ringOuter + margin
        let centre = Point2D(
            x: clamp(pointer.x, low: visible.minX + reach, high: visible.maxX - reach),
            y: clamp(pointer.y, low: visible.minY + reach, high: visible.maxY - reach))
        let side = geometry.panelSide
        let frame = Rect2D(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        let offset = Point2D(x: centre.x - pointer.x, y: centre.y - pointer.y)
        return PanelPlacement(screenIndex: index, wheelCentre: centre, panelFrame: frame, offset: offset)
    }

    /// When the visible frame is narrower than the disk, the disk is centred on it.
    private func clamp(_ value: Double, low: Double, high: Double) -> Double {
        guard low <= high else { return (low + high) / 2 }
        return min(max(value, low), high)
    }
}
