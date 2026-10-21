import AppKit
import Testing

@testable import ZivletActions

/// Answers `canPerform` as told and finishes `perform` with a fixed outcome, recording what it was given.
final class FakeSharing: SharingService {
    let available: Bool
    let result: SharingOutcome
    private(set) var performed: [[URL]] = []

    init(available: Bool = true, result: SharingOutcome = .sent) {
        self.available = available
        self.result = result
    }

    func canPerform(_ items: [URL]) -> Bool { available && !items.isEmpty }

    func perform(_ items: [URL], completion: @escaping (SharingOutcome) -> Void) {
        performed.append(items)
        Task { completion(result) }
    }
}

@Suite("AirDrop: availability, silent cancel, failures (P1-44)")
struct AirDropActionTests {
    let items = [URL(fileURLWithPath: "/etc/hosts")]

    @Test func unavailableNeverStartsSharing() async {
        let fake = FakeSharing(available: false)
        #expect(await AirDropAction(service: fake).send(items) == .failed(.airDropUnavailable))
        #expect(fake.performed.isEmpty)
        #expect(await AirDropAction(service: nil).send(items) == .failed(.airDropUnavailable))
    }

    @Test func successIsAToast() async {
        let fake = FakeSharing()
        #expect(await AirDropAction(service: fake).send(items) == .done(toast: "Sent with AirDrop"))
        #expect(fake.performed == [items])
    }

    @Test func userCancelIsSilent() async {
        let cancel = SharingOutcome.failed(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        #expect(await AirDropAction(service: FakeSharing(result: cancel)).send(items) == .cancelled)
        #expect(ActionOutcome.cancelled.toast == nil)
    }

    @Test func otherErrorsCarryTheirCode() async {
        let failure = SharingOutcome.failed(domain: NSPOSIXErrorDomain, code: 5)
        let outcome = await AirDropAction(service: FakeSharing(result: failure)).send(items)
        #expect(outcome == .failed(.airDropFailed(code: 5)))
        #expect(ActionError.airDropFailed(code: 5).userMessage == "Zivlet couldn't start AirDrop for these files.")
        #expect(ActionError.airDropFailed(code: 5).detail == "AirDrop reported error 5.")
        #expect(ActionError.airDropUnavailable.userMessage == "Zivlet couldn't start AirDrop for these files.")
        #expect(ActionError.airDropUnavailable.detail == nil)
    }

    @Test func theSystemServiceRefusesABogusNameAndAnEmptyList() {
        #expect(SystemSharingService(named: NSSharingService.Name("app.zivlet.no-such-service")) == nil)
        if let airDrop = SystemSharingService(named: .sendViaAirDrop) {
            #expect(!airDrop.canPerform([]))
        }
    }

    @Test func theSystemServiceReportsItsDelegateOnceAndLetsGo() throws {
        let service = try #require(SystemSharingService(named: .sendViaAirDrop))
        var outcomes: [SharingOutcome] = []
        service.track { outcomes.append($0) }
        #expect(service.isWaiting)
        service.finish(error: nil)
        service.finish(error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        #expect(outcomes == [.sent] && !service.isWaiting)
        service.track { outcomes.append($0) }
        service.finish(error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        #expect(outcomes == [.sent, .failed(domain: NSCocoaErrorDomain, code: NSUserCancelledError)])
    }
}
