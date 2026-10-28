import CoreGraphics
import EngineVision
import Synchronization

/// Answers each image with the next list of its script (the last one repeats) after `delay`, and counts the calls.
public final class ScriptedDetector: BarcodeDetecting {
    let answers: [[DetectedCode]]
    let delay: Duration
    private let count = Mutex(0)

    public init(_ answers: [[DetectedCode]], delay: Duration = .zero) {
        self.answers = answers
        self.delay = delay
    }

    /// One code per image, `payload` as QR.
    public convenience init(payloads: [String], delay: Duration = .zero) {
        self.init(payloads.map { [DetectedCode(payload: $0, symbology: "qr", top: 0.5)] }, delay: delay)
    }

    public var calls: Int { count.withLock { $0 } }

    public func detect(_ image: CGImage) async throws -> [DetectedCode] {
        let index = count.withLock { count in
            defer { count += 1 }
            return count
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        guard !answers.isEmpty else { return [] }
        return answers[min(index, answers.count - 1)]
    }
}
