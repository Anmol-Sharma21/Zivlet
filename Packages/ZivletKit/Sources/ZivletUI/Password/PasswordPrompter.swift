import AppKit
import SwiftUI
import ZivletCore

/// What a job asks for: the mode, the files' names and where the window opens (the wheel, the HUD card or the island;
/// nil for the pointer).
public struct PasswordRequest: Sendable, Equatable {
    public let mode: PasswordMode
    public let files: [String]
    public let near: CGPoint?

    public init(mode: PasswordMode, files: [String], near: CGPoint?) {
        self.mode = mode
        self.files = files
        self.near = near
    }
}

/// The answer: the typed secrets and the batch choice, Cancel, or no window because another tool's window is open
/// (it is brought forward instead). The receiver owns the secrets and wipes them when its batch ends (E9).
public enum PasswordAnswer: Sendable, Equatable {
    case secrets(JobSecrets, sameForAll: Bool)
    case cancelled
    case unavailable
}

/// Asks for passwords; `PasswordPrompter` in the app, a fake in tests of its callers.
public protocol PasswordPrompting: AnyObject {
    func ask(_ request: PasswordRequest) async -> PasswordAnswer
    /// The second sheet (17b §3.3): only `failed`, saying the password did not work. Files that opened are not redone.
    func retry(_ request: PasswordRequest, failed: [String]) async -> PasswordAnswer
}

/// What shows the sheet: `ToolWindowCoordinator`, so the sheet is the one tool window (A5's rule).
public protocol ToolWindowPresenting: AnyObject {
    @discardableResult
    func present(
        _ content: any WindowToolContent, near point: CGPoint?, replacing: (any WindowToolContent) -> Bool
    ) -> Bool
}

extension ToolWindowCoordinator: ToolWindowPresenting {}

/// Asking for a password from the wheel, the HUD or the island (P2-101, plan 20c B6, D-M7-15): the sheet opens as the
/// tool window's content near the request's point and answers when Apply or Cancel is pressed. One sheet at a time:
/// a second ask waits until the first has its answer. Earlier Read QR results give way; another tool's open window
/// does not (the answer is then `.unavailable`).
public final class PasswordPrompter: PasswordPrompting {
    private let presenter: any ToolWindowPresenting
    private let makeState: (PasswordSheetModel) -> PasswordSheetState
    private var asking = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// The sheet on screen now, if any (for the DEBUG demos and the tests).
    public private(set) var showing: PasswordSheetState?

    public init(
        presenter: any ToolWindowPresenting,
        makeState: @escaping (PasswordSheetModel) -> PasswordSheetState = { PasswordSheetState(model: $0) }
    ) {
        self.presenter = presenter
        self.makeState = makeState
    }

    public func ask(_ request: PasswordRequest) async -> PasswordAnswer {
        await show(PasswordSheetModel(mode: request.mode, files: request.files), near: request.near, wrong: false)
    }

    public func retry(_ request: PasswordRequest, failed: [String]) async -> PasswordAnswer {
        let model = PasswordSheetModel(mode: request.mode, files: request.files).retry(names: failed)
        return await show(model, near: request.near, wrong: true)
    }

    private func show(_ model: PasswordSheetModel, near point: CGPoint?, wrong: Bool) async -> PasswordAnswer {
        await takeTurn()
        defer { endTurn() }
        let state = makeState(model)
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<PasswordAnswer, Never>) in
            let content = PasswordSheetContent(state: state) { continuation.resume(returning: $0) }
            guard presenter.present(content, near: point, replacing: { $0 is CodeResultsContent }) else {
                return content.answer(.unavailable)
            }
            showing = state
            if wrong { state.wrongAttempt() }
        }
        showing = nil
        return answer
    }

    private func takeTurn() async {
        guard asking else {
            asking = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func endTurn() {
        guard !waiting.isEmpty else {
            asking = false
            return
        }
        waiting.removeFirst().resume()
    }
}

/// The sheet as a window tool's content: Apply (when it is on) answers with the secrets and closes the window; Cancel
/// empties the fields and answers with nothing. It answers once.
final class PasswordSheetContent: WindowToolContent {
    let state: PasswordSheetState
    var modelChanged: (ToolWindowModel) -> Void = { _ in }
    private var reply: ((PasswordAnswer) -> Void)?

    init(state: PasswordSheetState, reply: @escaping (PasswordAnswer) -> Void) {
        self.state = state
        self.reply = reply
        state.modelChanged = { [weak self] in self?.modelChanged($0.window) }
    }

    var model: ToolWindowModel { state.model.window }
    var view: AnyView { AnyView(PasswordSheetView(state: state)) }

    func apply() -> Bool {
        guard state.model.apply.isEnabled else { return false }
        let sameForAll = state.model.sameForAll
        answer(.secrets(state.takeSecrets(), sameForAll: sameForAll))
        return true
    }

    func cancel() {
        state.clearFields()
        answer(.cancelled)
    }

    func answer(_ answer: PasswordAnswer) {
        reply?(answer)
        reply = nil
    }
}
