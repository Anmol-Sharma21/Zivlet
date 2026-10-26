import Testing

@testable import ZivletShelfCore

/// One row per (state, event) for the Drop Box presentation (P2-55 §9.1, 19c §4.1), written out by hand from the
/// rules in `BoxPresentation`. A new event needs a name in `name(of:)` (the switch is exhaustive) and then a row in
/// every state, or `assertComplete` fails.
enum BoxPresentationTable {
    struct Row: Equatable, CustomStringConvertible {
        let base: BoxPresentation.Base
        let overlay: BoxPresentation.Overlay?
        let dock: DockEdge?
        let effects: [BoxPresentationEffect]

        var description: String { "\(base) \(String(describing: overlay)) \(String(describing: dock)) \(effects)" }
    }

    static let present: [BoxPresentationEffect] = [.present, .persist]
    static let dismiss: [BoxPresentationEffect] = [.dismiss, .persist]

    /// The states the table starts from: every base, and each overlay over the base it usually interrupts.
    static let states: [String: BoxPresentation] = [
        "hidden": BoxPresentation(base: .hidden),
        "docked": BoxPresentation(base: .docked(.left), dock: .left),
        "collapsed": BoxPresentation(base: .collapsed),
        "expanded": BoxPresentation(base: .expanded),
        "dropTarget": BoxPresentation(base: .docked(.left), overlay: .dropTarget(count: 3), dock: .left),
        "busy": BoxPresentation(base: .expanded, overlay: .busy(verb: "Moving", fraction: 0.4)),
        "confirm": BoxPresentation(base: .expanded, overlay: .confirm(.trash(count: 3))),
    ]

    static let events: [BoxPresentationEvent] = [
        .show, .hide, .dock(.right), .undock, .click, .escape, .dragEntered(count: 5), .dragExited, .dropped,
        .busyStarted(verb: "Copying"), .progress(0.5), .busyEnded, .confirmRequested(.clear), .confirmAnswered(true),
        .confirmAnswered(false), .itemsChanged(count: 12, missing: 2),
    ]

    static func name(of event: BoxPresentationEvent) -> String {
        switch event {
        case .show: "show"
        case .hide: "hide"
        case .dock: "dock"
        case .undock: "undock"
        case .click: "click"
        case .escape: "escape"
        case .dragEntered: "dragEntered"
        case .dragExited: "dragExited"
        case .dropped: "dropped"
        case .busyStarted: "busyStarted"
        case .progress: "progress"
        case .busyEnded: "busyEnded"
        case .confirmRequested: "confirmRequested"
        case .confirmAnswered(let yes): yes ? "confirmAnswered(yes)" : "confirmAnswered(no)"
        case .itemsChanged: "itemsChanged"
        }
    }

    static func same(_ state: String) -> Row {
        let p = states[state]!
        return Row(base: p.base, overlay: p.overlay, dock: p.dock, effects: [])
    }

    static func row(
        _ state: String, base: BoxPresentation.Base? = nil, overlay: BoxPresentation.Overlay?? = nil,
        dock: DockEdge?? = nil, effects: [BoxPresentationEffect] = []
    ) -> Row {
        let p = states[state]!
        return Row(base: base ?? p.base, overlay: overlay ?? p.overlay, dock: dock ?? p.dock, effects: effects)
    }

    /// Every event is "same" unless a state lists it.
    static func rows(_ state: String, _ changes: [String: Row]) -> [String: Row] {
        var all = Dictionary(uniqueKeysWithValues: events.map { (name(of: $0), same(state)) })
        all.merge(changes) { _, new in new }
        return all
    }

    static var table: [String: [String: Row]] {
        [
            "hidden": rows("hidden", ["show": row("hidden", base: .expanded, effects: present)]),
            "docked": rows("docked", dockedRows),
            "collapsed": rows("collapsed", collapsedRows),
            "expanded": rows("expanded", expandedRows),
            "dropTarget": rows("dropTarget", dropTargetRows),
            "busy": rows("busy", busyRows),
            "confirm": rows("confirm", confirmRows),
        ]
    }

    static var dockedRows: [String: Row] {
        [
            "show": row("docked", base: .expanded, effects: present),
            "hide": row("docked", base: .hidden, effects: dismiss),
            "dock": row("docked", base: .docked(.right), dock: .right, effects: present),
            "undock": row("docked", base: .expanded, dock: .some(nil), effects: present),
            "click": row("docked", base: .expanded, effects: present),
            "dragEntered": row("docked", overlay: .dropTarget(count: 5)),
            "busyStarted": row("docked", overlay: .busy(verb: "Copying", fraction: 0)),
        ]
    }

    static var collapsedRows: [String: Row] {
        [
            "show": row("collapsed", base: .expanded, effects: present),
            "hide": row("collapsed", base: .hidden, effects: dismiss),
            "dock": row("collapsed", base: .docked(.right), dock: .right, effects: present),
            "click": row("collapsed", base: .expanded, effects: present),
            "escape": row("collapsed", base: .hidden, effects: dismiss),
            "dragEntered": row("collapsed", overlay: .dropTarget(count: 5)),
            "busyStarted": row("collapsed", overlay: .busy(verb: "Copying", fraction: 0)),
        ]
    }

    static var expandedRows: [String: Row] {
        [
            "hide": row("expanded", base: .hidden, effects: dismiss),
            "dock": row("expanded", base: .docked(.right), dock: .right, effects: present),
            "escape": row("expanded", base: .collapsed, effects: present),
            "dragEntered": row("expanded", overlay: .dropTarget(count: 5)),
            "busyStarted": row("expanded", overlay: .busy(verb: "Copying", fraction: 0)),
            "confirmRequested": row("expanded", overlay: .confirm(.clear)),
        ]
    }

    static var dropTargetRows: [String: Row] {
        [
            "show": row("dropTarget", base: .expanded, effects: present),
            "hide": row("dropTarget", base: .hidden, overlay: .some(nil), effects: dismiss),
            "dock": row("dropTarget", base: .docked(.right), dock: .right, effects: present),
            "undock": row("dropTarget", base: .expanded, dock: .some(nil), effects: present),
            "click": row("dropTarget", base: .expanded, effects: present),
            "dragEntered": row("dropTarget", overlay: .dropTarget(count: 5)),
            "dragExited": row("dropTarget", overlay: .some(nil)),
            "dropped": row("dropTarget", base: .expanded, overlay: .some(nil), effects: present),
        ]
    }

    static var busyRows: [String: Row] {
        [
            "hide": row("busy", base: .hidden, overlay: .some(nil), effects: dismiss),
            "dock": row("busy", base: .docked(.right), dock: .right, effects: present),
            "escape": row("busy", effects: [.cancelBusy]),
            "busyStarted": row("busy", overlay: .busy(verb: "Copying", fraction: 0)),
            "progress": row("busy", overlay: .busy(verb: "Moving", fraction: 0.5)),
            "busyEnded": row("busy", overlay: .some(nil)),
        ]
    }

    static var confirmRows: [String: Row] {
        [
            "hide": row("confirm", base: .hidden, overlay: .some(nil), effects: dismiss),
            "dock": row("confirm", base: .docked(.right), overlay: .some(nil), dock: .right, effects: present),
            "escape": row("confirm", overlay: .some(nil)),
            "busyStarted": row("confirm", overlay: .busy(verb: "Copying", fraction: 0)),
            "confirmRequested": row("confirm", overlay: .confirm(.clear)),
            "confirmAnswered(yes)": row("confirm", overlay: .some(nil), effects: [.confirmed(.trash(count: 3))]),
            "confirmAnswered(no)": row("confirm", overlay: .some(nil)),
        ]
    }

    /// Every state has a row for every event, and every row holds.
    static func assertComplete() {
        let names = Set(events.map(name(of:)))
        #expect(Set(table.keys) == Set(states.keys))
        for (stateName, rows) in table {
            #expect(Set(rows.keys) == names, "state \(stateName) lacks a row")
            for event in events {
                let (next, effects) = states[stateName]!.handling(event)
                let got = Row(base: next.base, overlay: next.overlay, dock: next.dock, effects: effects)
                #expect(got == rows[name(of: event)], "\(stateName) × \(name(of: event))")
            }
        }
    }
}
