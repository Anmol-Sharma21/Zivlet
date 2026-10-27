import CoreGraphics
import Foundation
import ZivletActions
import ZivletCore
import ZivletRuntime

/// Shows conversion batches: today's card near the drop (`ResultHUD`) or the notch island (`NotchHUD`). The wiring
/// picks one per drop (D-M5a-8) and gives both the same closures.
public protocol HUDPresenter: AnyObject {
    var onCancel: (BatchID) -> Void { get set }
    var onReveal: ([URL]) -> Void { get set }
    var onOpen: ([URL]) -> Void { get set }
    var onCopy: ([URL]) -> Void { get set }
    /// Retry pressed on a failed batch: the source batch and where its drop was, so the wiring can route the new
    /// batch to the same place.
    var onRetry: (BatchID, CGPoint?) -> Void { get set }
    var onUndo: (BatchID) async -> UndoReply { get set }

    /// A drop happened at `point` (nil = no drop); the next new batch opens there.
    func prepare(near point: CGPoint?)
    func show(_ snapshot: BatchSnapshot)
    func close(_ batch: BatchID)
}

/// Shows action results (D-M5a-3): today's small panel near the drop (`ActionHUD`) or the notch island.
public protocol ActionPresenter: AnyObject {
    var onUndo: (BatchID) async -> UndoReply { get set }
    /// A button of Copy Text's card was pressed (P2-104).
    var onTextButton: (TextResultButton, TextOutcome) -> Void { get set }
    func show(_ result: ActionResult, near point: CGPoint?)
    /// A long action's one working line ("Recognising text… 40%") with Cancel; the next result takes its place. A
    /// press of Cancel removes the line and runs `cancel`.
    func showWorking(_ status: WorkingStatus, near point: CGPoint?, cancel: @escaping () -> Void)
}
