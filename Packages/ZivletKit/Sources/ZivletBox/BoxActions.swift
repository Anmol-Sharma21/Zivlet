import AppKit
import ZivletActions

/// The actions the box's bulk commands run (P2-142): the wheel's own actions, reused, never copied. Every one is a
/// port, so the controller is tested with fakes and a private pasteboard.
public struct BoxActions {
    public let sharePicker: any SharePicking
    public let clipboard: ClipboardAction
    public let airDrop: AirDropAction
    /// ⌥ is held now: Copy Paths from the menu writes the shell-quoted form, as the wheel's Copy Path slice does.
    public let optionHeld: () -> Bool
    /// Waits one run-loop turn, so the panel's click is over before AirDrop's sheet takes focus.
    public let nextTurn: ActionService.NextTurn
    /// Move to… and Copy to…: the wheel's own path, with the folder chooser and the undo history.
    public let service: ActionService

    public init(
        sharePicker: any SharePicking = SystemSharePicker(), clipboard: ClipboardAction = ClipboardAction(),
        airDrop: AirDropAction = AirDropAction(),
        optionHeld: @escaping () -> Bool = { NSEvent.modifierFlags.contains(.option) },
        nextTurn: @escaping ActionService.NextTurn = ActionService.runLoopTurn, service: ActionService
    ) {
        self.sharePicker = sharePicker
        self.clipboard = clipboard
        self.airDrop = airDrop
        self.optionHeld = optionHeld
        self.nextTurn = nextTurn
        self.service = service
    }

    func copy(_ urls: [URL]) -> ActionResult { ActionResult(clipboard.copyItems(urls)) }

    func copyPaths(_ urls: [URL], shellQuoted: Bool) -> ActionResult {
        ActionResult(clipboard.copyPaths(urls, shellQuoted: shellQuoted))
    }

    func move(_ urls: [URL]) async -> (ActionResult, MoveReport?) { await service.moveReporting(urls) }

    func send(_ urls: [URL]) async -> ActionResult {
        await nextTurn()
        return ActionResult(await airDrop.send(urls))
    }
}
