import AppKit
import Observation

/// What changes on a shown card after it appears: the undo reply, the details disclosure, the thumbnail.
@Observable
public final class CardState {
    public internal(set) var undoMessage: String?
    /// The last undo left files the Trash refused, so Undo stays available.
    public internal(set) var undoCanRetry = false
    /// Undo was pressed and its reply has not come back; a second press is ignored.
    public internal(set) var undoInFlight = false
    /// Paths of outputs an undo put in the Trash; nothing on the card acts on them any more.
    public internal(set) var removedPaths: Set<String> = []
    public internal(set) var showsDetails = false
    public internal(set) var thumbnail: NSImage?

    public init() {}

    /// The outputs still where they were saved.
    func remaining(_ outputs: [URL]) -> [URL] { outputs.filter { !removedPaths.contains(Self.key($0)) } }

    func remove(_ outputs: [URL]) { removedPaths.formUnion(outputs.map(Self.key)) }

    /// URLs from the undo log and from the snapshot may differ in form; their standardized paths do not.
    static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    /// The model's buttons on screen now: Undo until it has answered (and again when the Trash refused something),
    /// never while it runs; Reveal, Open and Copy while an output is left; Show Details until the details show.
    func visible(_ model: ResultCardModel) -> [ResultCardModel.Button] {
        let hasOutputs = !remaining(model.outputs).isEmpty
        return model.buttons.filter { button in
            switch button {
            case .undo: !undoInFlight && (undoMessage == nil || undoCanRetry)
            case .reveal, .open, .copy: hasOutputs
            case .showDetails: !showsDetails
            case .retry, .close: true
            }
        }
    }
}
