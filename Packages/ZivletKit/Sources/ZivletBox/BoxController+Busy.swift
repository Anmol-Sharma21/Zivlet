import Foundation
import ZivletActions
import ZivletShelfCore

/// The busy overlay of the long bulk actions (G-M5b-9, 19c §4.1): the verb and a bar while the work runs, Cancel and
/// Esc to stop it. Progress arrives on the worker's thread and is drawn on the main actor at most every 50 ms, the
/// latest value winning; the overlay always goes when the work ends, however it ends.
extension BoxController {
    /// The shortest time between two redraws of the bar.
    static let progressInterval = Duration.milliseconds(50)

    /// Runs `work` as the bulk action, handing it a progress port that drives the overlay. The overlay appears only
    /// when the work says it started (after any chooser), with `verb(count)`.
    func runBusy(_ verb: @escaping (Int) -> String, _ work: @escaping (TransferProgress) async -> Void) {
        runBulk { [weak self] in
            guard let self else { return }
            let (fractions, sink) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
            let drawing = Task { [weak self] in
                for await fraction in fractions {
                    self?.apply(.progress(fraction))
                    try? await Task.sleep(for: Self.progressInterval)
                }
            }
            let progress = TransferProgress(
                started: { [weak self] count in self?.apply(.busyStarted(verb: verb(count))) },
                advanced: { done, total in sink.yield(total > 0 ? Double(done) / Double(total) : 1) })
            await work(progress)
            sink.finish()
            drawing.cancel()
            await drawing.value
            apply(.busyEnded)
        }
    }
}
