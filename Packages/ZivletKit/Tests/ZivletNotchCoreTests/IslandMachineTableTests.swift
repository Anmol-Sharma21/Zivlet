import Testing
import ZivletNotchCore

/// Every event in every state (design/19 §4.2): a new `IslandEvent` case without rows here fails the coverage test.
@Suite("Island machine: every event in every state")
struct IslandMachineTableTests {
    enum State: String, CaseIterable {
        case hidden, collapsed, toast, hoverExpanded, focusExpanded, dragHeld, pinned, keyed, keyedLeaving, suppressed
        case sensor, dropTarget
    }

    static let t0 = Duration.seconds(100)
    static let t1 = t0 + .seconds(5)
    static let intent = t1 + .milliseconds(150)
    static let grace = t1 + .milliseconds(300)

    static func machine(_ state: State) -> IslandMachine {
        let collapsed = IslandMachine.showing(.collapsed, at: t0)
        let hoverExpanded = collapsed.after([.pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150))])
        switch state {
        case .hidden: return IslandMachine()
        case .collapsed: return collapsed
        case .toast: return IslandMachine.showing(.toast, at: t0)
        case .hoverExpanded: return hoverExpanded
        case .focusExpanded: return collapsed.after([.accessibilityFocused(now: t0)])
        case .dragHeld:
            return hoverExpanded.after([
                .dragBegan(now: t0 + .seconds(1)), .pointerExited(now: t0 + .seconds(1)), .tick(now: t0 + .seconds(2)),
            ])
        case .pinned: return collapsed.after([.expandRequested(now: t0)])
        case .keyed: return hoverExpanded.after([.clicked(now: t0 + .seconds(1))])
        case .keyedLeaving:
            return hoverExpanded.after([.clicked(now: t0 + .seconds(1)), .pointerExited(now: t0 + .seconds(2))])
        case .suppressed: return collapsed.after([.wheelShown(now: t0)])
        case .sensor:
            return IslandMachine().after([.request(.tray(.sensor), now: t0), .contentHeightChanged(108, now: t0)])
        case .dropTarget:
            return IslandMachine().after([.request(.trayDrop(), now: t0), .contentHeightChanged(108, now: t0)])
        }
    }

    /// The events sent in each state, by label: every case of `IslandEvent.allCases`, plus four more requests (the
    /// HUD's toast and tab, the tray's sensor and drop target).
    static var events: [(String, IslandEvent)] {
        IslandEvent.allCases(now: t1).map { (label($0), $0) } + [
            ("request(toast)", .request(.hud(.toast), now: t1)),
            ("request(collapsed)", .request(.hud(.collapsed), now: t1)),
            ("request(sensor)", .request(.tray(.sensor), now: t1)),
            ("request(dropTarget)", .request(.trayDrop(), now: t1)),
        ]
    }

    static func label(_ event: IslandEvent) -> String {
        if case .request(nil, _) = event { return "request(nil)" }
        return "\(event.kind)"
    }

    struct Row {
        let surface: IslandSurface
        let effects: [IslandEffect]
    }

    static func show(_ surface: IslandSurface, _ height: Double = 108) -> IslandEffect {
        .show(surface, display: 1, contentHeight: height)
    }

    static let same: [IslandEffect] = []

    @Test func everyEventInEveryStateHasARowAndMatchesIt() {
        for state in State.allCases {
            let rows = Self.table[state] ?? [:]
            for (label, event) in Self.events {
                guard let row = rows[label] else {
                    Issue.record("no row for \(label) in \(state)")
                    continue
                }
                let (next, effects) = Self.machine(state).handling(event)
                #expect(next.surface == row.surface, "\(state) + \(label): surface")
                #expect(effects == row.effects, "\(state) + \(label): effects")
            }
        }
    }

    @Test func theTableHasNoRowsForEventsThatDoNotExist() {
        let labels = Set(Self.events.map(\.0))
        for (state, rows) in Self.table {
            #expect(Set(rows.keys).isSubset(of: labels), "\(state) has rows for unknown events")
        }
    }
}
