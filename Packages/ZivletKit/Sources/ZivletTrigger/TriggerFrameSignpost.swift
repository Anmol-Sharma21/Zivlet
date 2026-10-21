import os

/// The `trigger→frame` signpost (P1-24, 10 §8.7): from the moment the trigger machine turns a tap into a wheel show
/// to the wheel's first displayed frame. The trigger host (or the DEBUG demo) begins it; the wheel ends it from its
/// first display-link callback. A new show before the frame ends the old interval first, so none is left open.
@MainActor
public final class TriggerFrameSignpost {
    public static let shared = TriggerFrameSignpost()
    static let name: StaticString = "trigger→frame"

    private let signposter = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "wheel")
    private var pending: OSSignpostIntervalState?

    public init() {}

    public var isPending: Bool { pending != nil }

    public func begin() {
        end()
        pending = signposter.beginInterval(Self.name, id: signposter.makeSignpostID())
    }

    /// Ends the open interval; false when there was none (a wheel shown without a tap, for example the prewarm).
    @discardableResult
    public func end() -> Bool {
        guard let state = pending else { return false }
        signposter.endInterval(Self.name, state)
        pending = nil
        return true
    }
}
