import AppKit
import NotchTestSupport
import SwiftUI
import ZivletNotchCore

@testable import ZivletNotch

/// A client whose content is a few lines of text; it records what the island tells it.
@MainActor
final class FakeClient: IslandClient {
    var lines = 3
    let name: String
    private(set) var held: [Bool] = []
    private(set) var closed: [UInt32] = []
    private(set) var displayChanges: [(ids: [UInt32], replacing: [UInt32: UInt32])] = []
    private(set) var actions = 0

    init(name: String = "fake") { self.name = name }

    func content(for surface: IslandSurface, display: UInt32) -> AnyView {
        let name = self.name
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<lines, id: \.self) { Text("\(name) line \($0)") }
            }
            .padding(10))
    }

    func accessibilityLabel(display: UInt32) -> String { "Fake island" }
    func accessibilityValue(display: UInt32) -> String { "\(lines) lines" }
    var accessibilityActionName: String { "Show Fake" }
    func accessibilityActionPerformed(display: UInt32) { actions += 1 }
    func held(_ held: Bool, display: UInt32, now: Duration) { self.held.append(held) }
    func closeRequested(display: UInt32) { closed.append(display) }
    func displaysChanged(_ ids: [UInt32], replacing: [UInt32: UInt32]) { displayChanges.append((ids, replacing)) }
}

/// What a host sent to its machine.
@MainActor
final class EventLog {
    private(set) var events: [IslandEvent] = []
    func record(_ event: IslandEvent) { events.append(event) }
    var kinds: [IslandEvent.Kind] { events.map(\.kind) }
    func clear() { events = [] }
}

/// A pointer location the test moves.
@MainActor
final class FakePointer {
    var location = CGPoint(x: -20_000, y: -20_000)
}

@MainActor
func makeHost(
    _ display: DisplayGeometry, client: FakeClient = FakeClient(), motion: IslandAnimation = .instant,
    clock: any MonotonicClock = ManualClock(), pointer: FakePointer = FakePointer(), log: EventLog = EventLog()
) -> IslandHost {
    let host = IslandHost(
        display: display, client: client, motion: motion, clock: clock, pointer: { pointer.location })
    host.onEvent = { log.record($0) }
    return host
}

/// Waits (by turns of the main actor) until `condition` holds, for at most about a second.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
