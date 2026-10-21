import ZivletCore
import ZivletWheelCore

/// How a practice lesson stands.
public enum PracticeOutcome: Sendable, Equatable {
    case waiting
    case wrongMode(expected: WheelMode)
    case done
}

/// One lesson: open the taught wheel and drop on it once (03b §8.2). The selection itself is never run.
public struct PracticeState: Sendable, Equatable {
    public let teaching: WheelMode
    public let outcome: PracticeOutcome
    /// The wheel the last selection came from.
    public let received: WheelMode?

    public init(teaching: WheelMode, outcome: PracticeOutcome = .waiting, received: WheelMode? = nil) {
        self.teaching = teaching
        self.outcome = outcome
        self.received = received
    }

    public func receiving(_ selection: WheelSelection) -> PracticeState {
        guard outcome != .done else { return self }
        let outcome: PracticeOutcome = selection.mode == teaching ? .done : .wrongMode(expected: teaching)
        return PracticeState(teaching: teaching, outcome: outcome, received: selection.mode)
    }
}

/// The lessons of one practice page, taught in turn: Convert on page 2, Tools then Actions on page 3.
struct PracticeCoordinator: Sendable, Equatable {
    let lessons: [WheelMode]
    let index: Int
    let state: PracticeState

    init?(page: OnboardingPage) {
        switch page {
        case .practiceConvert: self.init(lessons: [.convert], index: 0)
        case .practiceToolsActions: self.init(lessons: [.tools, .actions], index: 0)
        default: return nil
        }
    }

    private init(lessons: [WheelMode], index: Int, state: PracticeState? = nil) {
        self.lessons = lessons
        self.index = index
        self.state = state ?? PracticeState(teaching: lessons[index])
    }

    var isFinished: Bool { state.outcome == .done && index == lessons.count - 1 }

    /// A finished lesson moves on to the next one, if any.
    func receiving(_ selection: WheelSelection) -> PracticeCoordinator {
        let next = state.receiving(selection)
        guard next.outcome == .done, index + 1 < lessons.count else {
            return PracticeCoordinator(lessons: lessons, index: index, state: next)
        }
        return PracticeCoordinator(lessons: lessons, index: index + 1)
    }

    /// Zivlet's own coaching line for the current state.
    func message(keyCap: (WheelMode) -> String) -> String {
        let taught = state.teaching
        switch state.outcome {
        case .done: return "That's it."
        case .wrongMode(let expected):
            let got = state.received.map(Self.name) ?? "another"
            return "That was the \(got) wheel. Tap \(keyCap(expected)) for \(Self.name(expected))."
        case .waiting where index == 0: return "Drag the sample and tap \(keyCap(taught))."
        case .waiting: return "Now try \(keyCap(taught)) for \(Self.name(taught))."
        }
    }

    static func name(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: "Convert"
        case .tools: "Tools"
        case .actions: "Actions"
        }
    }
}
