import EngineTestSupport
import EngineVision
import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletRuntime

/// A locked PDF's password goes with that file's own Copy Text or Read QR job, through the loopback worker, and is
/// wiped when the job ends (P2-107, plan 20f E10).
@Suite("A locked input's job carries its password")
struct LockedInputServiceTests {
    static func password(_ prefix: String) -> String { "\(prefix)-\(UUID().uuidString.prefix(10))" }

    @Test func copyTextSkipsALockedPDFUntilItsPasswordComes() async throws {
        let rig = try TextRig()
        let user = Self.password("user")
        let pdf = try PDFFixtures.encrypted(
            in: rig.dir.url, name: "Lease.pdf", keyLength: 128, user: user, owner: Self.password("owner"))

        let first = try await rig.service.copyText([pdf], languages: [.english])
        #expect(first.skipped == [SkippedFile(name: "Lease.pdf", error: .pdfLocked)])

        let wrong = JobSecret(utf8: Self.password("wrong"))
        let still = try await rig.service.copyText([pdf], languages: [.english], secrets: JobSecrets(input: wrong))
        #expect(still.skipped.map(\.error) == [.pdfLocked])
        #expect(wrong.isWiped)

        let right = JobSecret(utf8: user)
        let text = try await rig.service.copyText([pdf], languages: [.english], secrets: JobSecrets(input: right))
        #expect(text.skipped.isEmpty)
        // These short pages go to recognition, so the scripted text comes back for each: the file was opened.
        #expect(text.perFile.map(\.name) == ["Lease.pdf"] && !text.text.isEmpty)
        #expect(right.isWiped)
    }

    @Test func readQROpensALockedPDFWithItsPassword() async throws {
        let rig = try CodeRig(payloads: ["https://zivlet.app/locked"])
        let user = Self.password("user")
        let pdf = try PDFFixtures.encrypted(
            in: rig.dir.url, name: "Menu.pdf", keyLength: 128, user: user, owner: Self.password("owner"))

        #expect(try await rig.service.readCodes([pdf]).first?.error == .pdfLocked)
        let secret = JobSecret(utf8: user)
        let files = try await rig.service.readCodes([pdf], secrets: JobSecrets(input: secret))
        #expect(files.first?.error == nil)
        #expect(secret.isWiped)
    }
}
