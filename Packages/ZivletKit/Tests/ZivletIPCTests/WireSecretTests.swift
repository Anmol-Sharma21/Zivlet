import Foundation
import Testing
import ZivletCore
@testable import ZivletIPC

/// A password on the worker's wire (plan 20c B1, D-M7-14): bytes inside the one request of its job, rebuilt as a
/// `JobSecret` on the other side, never shown in a description.
@Suite("A password crosses to the worker as bytes and stays hidden")
struct WireSecretTests {
    private let password = "zv-test-" + UUID().uuidString

    private struct Carrier: Codable, Equatable {
        let job: String
        let secret: WireSecret
    }

    @Test func aRoundTripThroughJSONGivesTheSameBytes() throws {
        let carrier = Carrier(job: "lock", secret: WireSecret(JobSecret(utf8: password)))
        let decoded = try JSONDecoder().decode(Carrier.self, from: JSONEncoder().encode(carrier))
        #expect(decoded == carrier)
        #expect(decoded.secret.secret().withBytes { Array($0) } == Array(password.utf8))
    }

    @Test func nonASCIIBytesSurviveTheWire() throws {
        let text = "पासवर्ड-" + password
        let wire = WireSecret(JobSecret(utf8: text))
        let decoded = try JSONDecoder().decode(WireSecret.self, from: JSONEncoder().encode(wire))
        #expect(decoded.secret().withBytes { Array($0) } == Array(text.utf8))
    }

    @Test func theWireFormCarriesBytesNotTheText() throws {
        let data = try JSONEncoder().encode(WireSecret(JobSecret(utf8: password)))
        #expect(String(decoding: data, as: UTF8.self).contains(password) == false)
    }

    @Test func everyDescriptionHidesTheBytesAndTheirLength() {
        let carrier = Carrier(job: "lock", secret: WireSecret(JobSecret(utf8: password)))
        var dumped = ""
        dump(carrier, to: &dumped)
        let texts = [String(describing: carrier), String(reflecting: carrier), dumped]
        #expect(texts.allSatisfy { !$0.contains(password) && !$0.contains("bytes") })
        #expect(String(describing: carrier.secret) == JobSecret.redacted)
    }

    @Test func aWipedSecretGoesOnTheWireAsZeros() {
        let secret = JobSecret(utf8: password)
        secret.wipe()
        #expect(WireSecret(secret).secret().withBytes { $0.allSatisfy { $0 == 0 } })
    }
}
