import AppKit

/// How a share ended, as the sharing service reports it.
public enum SharingOutcome: Sendable, Equatable {
    case sent
    case failed(domain: String, code: Int)
}

/// The sharing calls AirDrop needs, so tests run without the system sheet.
public protocol SharingService: AnyObject {
    func canPerform(_ items: [URL]) -> Bool
    /// Starts sharing; `completion` runs once, on the main actor, when the service is done.
    func perform(_ items: [URL], completion: @escaping (SharingOutcome) -> Void)
}

/// AirDrop (P1-44, 03b §7 row 1): an availability check first, then the system AirDrop sheet. Cancelling the sheet
/// is silent; any other failure keeps its code for "Show details".
public struct AirDropAction {
    private let service: (any SharingService)?

    public init(service: (any SharingService)? = SystemSharingService(named: .sendViaAirDrop)) {
        self.service = service
    }

    public func send(_ items: [URL]) async -> ActionOutcome {
        guard let service, service.canPerform(items) else { return .failed(.airDropUnavailable) }
        let outcome = await withCheckedContinuation { continuation in
            service.perform(items) { continuation.resume(returning: $0) }
        }
        return Self.outcome(outcome)
    }

    static func outcome(_ sharing: SharingOutcome) -> ActionOutcome {
        switch sharing {
        case .sent: .done(toast: "Sent with AirDrop")
        case .failed(let domain, let code) where domain == NSCocoaErrorDomain && code == NSUserCancelledError:
            .cancelled
        case .failed(_, let code): .failed(.airDropFailed(code: code))
        }
    }
}

/// `NSSharingService` behind `SharingService`. It keeps itself alive from `perform` until the delegate reports,
/// because the system holds its delegate weakly.
public final class SystemSharingService: NSObject, SharingService, NSSharingServiceDelegate {
    private let service: NSSharingService
    private var completion: ((SharingOutcome) -> Void)?
    private var retainedSelf: SystemSharingService?

    public init?(named name: NSSharingService.Name) {
        guard let service = NSSharingService(named: name) else { return nil }
        self.service = service
        super.init()
        service.delegate = self
    }

    var isWaiting: Bool { completion != nil }

    public func canPerform(_ items: [URL]) -> Bool {
        !items.isEmpty && service.canPerform(withItems: items)
    }

    public func perform(_ items: [URL], completion: @escaping (SharingOutcome) -> Void) {
        track(completion)
        service.perform(withItems: items)
    }

    public func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(error: nil)
    }

    public func sharingService(
        _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error
    ) {
        finish(error: error)
    }

    func track(_ completion: @escaping (SharingOutcome) -> Void) {
        self.completion = completion
        retainedSelf = self
    }

    /// Reports once; later calls (a second delegate message) are ignored.
    func finish(error: (any Error)?) {
        guard let completion else { return }
        self.completion = nil
        retainedSelf = nil
        let nsError = error.map { $0 as NSError }
        completion(nsError.map { .failed(domain: $0.domain, code: $0.code) } ?? .sent)
    }
}
