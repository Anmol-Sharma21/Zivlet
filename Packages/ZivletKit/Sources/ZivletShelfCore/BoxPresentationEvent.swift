/// What can happen to the Drop Box panel (P2-55 §9.1, 17e §2.3, 19c §4.1). The controller turns clicks, keys,
/// drags and action progress into these; `BoxPresentation.handling(_:)` decides what the panel shows next.
public enum BoxPresentationEvent: Sendable, Equatable {
    /// The menu command, the BOX slice, shake or the tray asked for the box.
    case show
    case hide
    /// The panel was let go within the attach distance of an edge.
    case dock(DockEdge)
    /// The panel was pulled past the detach distance.
    case undock
    /// A click on the docked tab or the collapsed card.
    case click
    /// Esc or ⌘W while the panel is key.
    case escape
    /// A file drag entered the panel; `count` is the pasteboard's item count, read without touching the files.
    case dragEntered(count: Int)
    case dragExited
    case dropped
    /// A bulk action started, with its verb ("Moving", "Copying").
    case busyStarted(verb: String)
    case progress(Double)
    case busyEnded
    /// Move to Trash of more than one item, or Clear, asks first (19c D-BL9).
    case confirmRequested(ConfirmKind)
    /// The person answered the inline confirmation: true runs the action.
    case confirmAnswered(Bool)
    /// The current box changed: how many items it holds and how many cannot be used now.
    case itemsChanged(count: Int, missing: Int)
}

/// What the inline confirmation asks about (19c §4.1 Confirm).
public enum ConfirmKind: Sendable, Equatable {
    case trash(count: Int)
    case clear
    /// Empty Box Storage: every box's owned copies go to the Trash.
    case emptyStorage
}

/// What the controller does after an event, besides drawing the new presentation.
public enum BoxPresentationEffect: Sendable, Equatable {
    /// The panel is on screen with a new base: order it front and lay out its frame for that base.
    case present
    /// Order the panel out; the box itself stays.
    case dismiss
    /// The base or the dock edge changed: save them, so a relaunch restores the panel (P2-55 §9.5).
    case persist
    /// The person agreed: run the action.
    case confirmed(ConfirmKind)
    /// Esc during a bulk action: stop it.
    case cancelBusy
}
