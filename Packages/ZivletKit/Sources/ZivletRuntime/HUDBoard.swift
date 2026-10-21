import Foundation
import ZivletCore

/// Which batch the single result HUD shows (03a §4.5) when several run at once. Pure and immutable.
///
/// A finished batch with failures stays on screen until it is dismissed, oldest first, so a newer batch never hides
/// a failure the user has not seen. Otherwise the newest batch still converting is shown, then the newest finished
/// one. The HUD's buttons act on `shown`, never on whichever batch reported last.
public struct HUDBoard: Sendable, Equatable {
    /// The latest snapshot of each batch, in the order the batches first appeared.
    public let snapshots: [BatchSnapshot]

    public init() { snapshots = [] }

    init(snapshots: [BatchSnapshot]) { self.snapshots = snapshots }

    public var shown: BatchSnapshot? {
        snapshots.first(where: \.needsAcknowledgement) ?? snapshots.last { !$0.isFinished } ?? snapshots.last
    }

    public func updating(_ snapshot: BatchSnapshot) -> HUDBoard {
        guard snapshots.contains(where: { $0.batch == snapshot.batch }) else {
            return HUDBoard(snapshots: snapshots + [snapshot])
        }
        return HUDBoard(snapshots: snapshots.map { $0.batch == snapshot.batch ? snapshot : $0 })
    }

    /// The user closed the batch's card.
    public func dismissing(_ batch: BatchID) -> HUDBoard {
        HUDBoard(snapshots: snapshots.filter { $0.batch != batch })
    }

    /// A finished batch's linger ran out. Ignored for batches still converting or with unseen failures.
    public func expiring(_ batch: BatchID) -> HUDBoard {
        guard let snapshot = snapshots.first(where: { $0.batch == batch }), snapshot.isFinished,
            !snapshot.needsAcknowledgement
        else { return self }
        return dismissing(batch)
    }
}

extension BatchSnapshot {
    /// Finished with at least one failure: the user must see it before it goes.
    var needsAcknowledgement: Bool { isFinished && !failures.isEmpty }
}
