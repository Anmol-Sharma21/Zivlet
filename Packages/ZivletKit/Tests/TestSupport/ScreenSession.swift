import CoreGraphics

/// The login session's screen state, for tests that need the window server to hand out key focus. While the screen
/// is locked no window of ours can become key, so such a test cannot observe what it checks; it is skipped (and says
/// why) rather than failed. The demos skip their pictures for the same reason.
public enum ScreenSession {
    /// True while the session's screen is locked; false when the session reports nothing.
    public static var isLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// The comment a skipped test shows.
    public static let lockedReason = "The screen is locked, so no window can become key"
}
