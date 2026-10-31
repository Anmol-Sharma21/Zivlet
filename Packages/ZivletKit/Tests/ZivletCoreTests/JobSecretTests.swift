import Foundation
import Testing
import ZivletCore

/// A password in memory (P2-102, plan 20c B1, D-M7-14): its own buffer, wiped, never shown, never encodable.
@Suite("A job's password stays in its own buffer and never shows")
struct JobSecretTests {
    /// Random per run, so a match in any text cannot be a coincidence (index §6).
    private let password = "zv-test-" + UUID().uuidString

    private struct Holder {
        let name: String
        let secret: JobSecret
    }

    /// One secret can be both user and owner (D-M7-20), so a caller lends it twice, one lending inside the other.
    @Test func aSecretLentInsideItsOwnLendingDoesNotBlock() {
        let secret = JobSecret(utf8: "one")

        let total = secret.withBytes { outer in secret.withBytes { inner in outer.count + inner.count } }

        #expect(total == 6)
    }

    @Test func everyDescriptionOfASecretHidesItsText() {
        let secret = JobSecret(utf8: password)
        var dumped = ""
        dump(secret, to: &dumped)
        let texts = [String(describing: secret), String(reflecting: secret), "\(secret)", dumped]
        #expect(texts.allSatisfy { !$0.contains(password) })
        #expect(String(describing: secret) == JobSecret.redacted)
    }

    @Test func aStructHoldingASecretHidesItToo() {
        let holder = Holder(name: "Report.pdf", secret: JobSecret(utf8: password))
        var dumped = ""
        dump(holder, to: &dumped)
        let texts = [String(describing: holder), String(reflecting: holder), "\(holder)", dumped]
        #expect(texts.allSatisfy { !$0.contains(password) })
        #expect(texts.allSatisfy { $0.contains("Report.pdf") })
    }

    @Test func theDescriptionDoesNotGiveAwayTheLength() {
        let short = JobSecret(utf8: "a")
        let long = JobSecret(utf8: String(repeating: "a", count: 60))
        #expect(String(describing: short) == String(describing: long))
        #expect(String(reflecting: short) == String(reflecting: long))
    }

    @Test func theBytesAreTheUTF8OfTheText() {
        let secret = JobSecret(utf8: "café")
        #expect(secret.withBytes { Array($0) } == Array("café".utf8))
    }

    @Test func aSecretCanBeMadeFromBytes() {
        let bytes: [UInt8] = [0x70, 0x00, 0xFF]
        #expect(JobSecret(bytes: bytes).withBytes { Array($0) } == bytes)
    }

    @Test func wipingZeroesTheBufferInPlace() {
        let secret = JobSecret(utf8: password)
        let count = password.utf8.count
        secret.wipe()
        #expect(secret.isWiped)
        #expect(secret.withBytes { Array($0) } == [UInt8](repeating: 0, count: count))
    }

    @Test func aNewSecretIsNotWiped() {
        #expect(!JobSecret(utf8: password).isWiped)
    }

    @Test func wipingTwiceIsHarmless() {
        let secret = JobSecret(utf8: password)
        secret.wipe()
        secret.wipe()
        #expect(secret.withBytes { $0.allSatisfy { $0 == 0 } })
    }

    @Test func anEmptySecretIsEmpty() {
        let secret = JobSecret(utf8: "")
        #expect(secret.isEmpty)
        #expect(secret.withBytes { $0.count } == 0)
        #expect(!JobSecret(utf8: password).isEmpty)
    }

    @Test func aSecretIsNotEncodable() {
        let type: Any.Type = JobSecret.self
        #expect(!(type is any Encodable.Type))
        #expect(!(type is any Decodable.Type))
    }

    @Test func twoSecretsAreEqualOnlyWhenTheyAreTheSameOne() {
        let first = JobSecret(utf8: password)
        let second = JobSecret(utf8: password)
        #expect(first == first)
        #expect(first != second)
    }

    /// The 127-byte rule belongs to the sheet and the PDF validator (B2, E3), not to the type.
    @Test func aSecretLongerThanAPDFAllowsIsStillHeld() {
        let text = String(repeating: "x", count: 128)
        #expect(JobSecret(utf8: text).withBytes { $0.count } == 128)
    }

    @Test func aJobsSecretsWipeTogether() {
        let secrets = JobSecrets(
            input: JobSecret(utf8: password), newUser: JobSecret(utf8: password + "n"), owner: nil)
        secrets.wipeAll()
        #expect(secrets.input?.isWiped == true)
        #expect(secrets.newUser?.isWiped == true)
        #expect(secrets.owner == nil)
    }

    @Test func aJobsSecretsHideTheirText() {
        let secrets = JobSecrets(input: JobSecret(utf8: password))
        var dumped = ""
        dump(secrets, to: &dumped)
        #expect(![String(describing: secrets), String(reflecting: secrets), dumped].contains { $0.contains(password) })
    }
}
