import Foundation
import ZivletCore

/// Immutable wheel state (02 §7.7, 05 P0-27). Every change builds a new value; an unchanged hit returns `self`, so a
/// store that compares values re-renders only when the highlighted slot really changes (03a §2.4).
public struct WheelModel: Sendable, Equatable {
    public let mode: WheelMode
    public let content: WheelContent
    public let idleHubLabel: String
    /// More than one source item: the hub uses the compact style for idle text and slice labels alike (03a §2.2).
    public let hubIsCompact: Bool
    public let highlighted: Int?

    public init(
        mode: WheelMode, content: WheelContent, idleHubLabel: String, hubIsCompact: Bool = false,
        highlighted: Int? = nil
    ) {
        self.mode = mode
        self.content = content
        self.idleHubLabel = idleHubLabel
        self.hubIsCompact = hubIsCompact
        self.highlighted = highlighted.flatMap { content.slices.indices.contains($0) ? $0 : nil }
    }

    public var slices: [WheelSlice] { content.slices }
    public var highlightedSlice: WheelSlice? { highlighted.map { slices[$0] } }
    /// Hovering a slot shows its label in the hub; otherwise the idle text.
    public var hubLabel: String { highlightedSlice?.label ?? idleHubLabel }
    /// Nil → refuse the drop and let the source snap back (hub, outside, empty wheel).
    public var dropTarget: SliceTarget? { highlightedSlice?.target }

    /// Hit-test a point relative to the wheel centre (y up) with hysteresis against the current highlight.
    public func hit(_ point: Point2D, tester: WheelHitTester = WheelHitTester()) -> HitResult {
        tester.hitTest(point, count: slices.count, current: highlighted)
    }

    public func applying(_ hit: HitResult) -> WheelModel {
        let next = Self.slot(of: hit).flatMap { slices.indices.contains($0) ? $0 : nil }
        guard next != highlighted else { return self }
        return WheelModel(
            mode: mode, content: content, idleHubLabel: idleHubLabel, hubIsCompact: hubIsCompact, highlighted: next)
    }

    /// In-place mode switch: same anchor and hub text, highlight cleared (01-prd FR-6).
    public func switching(to mode: WheelMode, content: WheelContent) -> WheelModel {
        WheelModel(mode: mode, content: content, idleHubLabel: idleHubLabel, hubIsCompact: hubIsCompact)
    }

    public func selection(urls: [URL], optionHeld: Bool = false) -> WheelSelection? {
        guard let target = dropTarget, !urls.isEmpty else { return nil }
        return WheelSelection(mode: mode, target: target, urls: urls, optionHeld: optionHeld)
    }

    private static func slot(of hit: HitResult) -> Int? {
        if case .slot(let index) = hit { return index }
        return nil
    }
}
