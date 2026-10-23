/// The words of Settings › General › Progress and results (design/19 §6, *new*). The notch choice is named for the
/// Mac: a Mac that has never shown a built-in notch gets the top-centre pill, so it says "At the top of the screen".
/// OWN-HUD-2 is open: the second label is one constant.
enum PlacementCopy {
    static let section = "Progress and results"
    static let title = "Show progress and results:"
    static let nearDropLabel = "Near the drop"

    static func notchLabel(hasBuiltInNotch: Bool) -> String {
        hasBuiltInNotch ? "At the notch" : "At the top of the screen"
    }
}
