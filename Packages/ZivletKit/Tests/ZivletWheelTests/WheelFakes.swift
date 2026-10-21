import AppKit
import ZivletCore
import ZivletWheelCore

@testable import ZivletWheel

/// Counts feedback calls instead of buzzing the trackpad.
final class FakeFeedback: WheelFeedback {
    private(set) var events: [String] = []
    func highlightChanged() { events.append("highlight") }
    func modeSwitched() { events.append("switch") }
    func rejected() { events.append("reject") }
    func dropAccepted() { events.append("drop") }
}

final class FakeHaptics: NSObject, NSHapticFeedbackPerformer {
    private(set) var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []
    func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) { patterns.append(pattern) }
}

enum Fixtures {
    static let builder = SliceBuilder()

    static func model(_ mode: WheelMode = .convert, _ formats: [FormatID] = [.png]) -> WheelModel {
        let items = formats.map { SelectionItem($0) }
        return WheelModel(mode: mode, content: builder.content(for: mode, items: items), idleHubLabel: "photo.png")
    }

    static let appearance = WheelAppearance(
        theme: .solid, palette: AccentPalette(base: RGB(r: 0.2, g: 0.5, b: 0.9)), reduceMotion: true)
}

extension Fixtures {
    /// A convert wheel with `count` PNG-labelled slices (1…12), for layout and render tests.
    static func slices(_ count: Int, highlighted: Int? = nil) -> WheelModel {
        let slices = (0..<count).map { index in
            WheelSlice(id: "convert.\(index)", label: "F\(index)", symbolName: nil, target: .convert(.png), badge: nil)
        }
        return WheelModel(
            mode: .convert, content: .slices(slices), idleHubLabel: "2 PNG FILES", highlighted: highlighted)
    }
}

/// Polls a main-actor condition every 10 ms for up to `timeout`; parallel render tests can delay timers.
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
