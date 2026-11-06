import Foundation
import Testing

@testable import ZivletCore

/// The protect job (plan 20f E2, D-M7-19): one job per PDF, validated by the tool catalog, with names that say what
/// happened. A job never carries a password (D-M7-14): those travel beside it, for its own requests only.
@Suite("Protect jobs and their names (P2-106)")
struct ProtectJobTests {
    static let report = URL(fileURLWithPath: "/Users/me/Documents/Report.pdf")
    static let folder = report.deletingLastPathComponent()
    static let restrictions = PDFRestrictions(printing: .low, copying: false, editing: false)

    static let everyMode: [ProtectSpec] = [
        ProtectSpec(mode: .lock(nil)), ProtectSpec(mode: .lock(restrictions)), ProtectSpec(mode: .unlock),
        ProtectSpec(mode: .changePassword, keepRestrictions: true),
    ]

    static func request(_ format: FormatID = .pdf, _ spec: ProtectSpec = ProtectSpec(mode: .lock(nil))) throws
        -> JobRequest
    {
        let input = try InputItem(url: report.deletingPathExtension().appendingPathExtension("\(format)"), format: format, byteCount: 900)
        return try JobRequest(input: input, operation: .protect(spec), destination: folder)
    }

    @Test(arguments: everyMode)
    func aProtectJobOnAPDFIsValidAndItsPairIsPDFToPDF(spec: ProtectSpec) throws {
        let request = try Self.request(.pdf, spec)
        #expect(request.target == .pdf)
        #expect(request.pair == ConversionPair(source: .pdf, target: .pdf))
        #expect(request.operation == .protect(spec))
    }

    @Test func aProtectJobOnAPNGIsRefused() {
        #expect(throws: JobError.pairNotSupported(.png, .pdf)) { try Self.request(.png) }
    }

    @Test func restrictionsDefaultToNoneAndKeepNothingByDefault() {
        let spec = ProtectSpec(mode: .lock(nil))
        #expect(spec.keepRestrictions == false)
        #expect(PDFRestrictions.none == PDFRestrictions(printing: .full, copying: true, editing: true))
    }

    @Test func everyModeRoundTripsAndNoKeyNamesAPassword() throws {
        for spec in Self.everyMode {
            let request = try Self.request(.pdf, spec)
            let data = try JSONEncoder().encode(request)
            #expect(try JSONDecoder().decode(JobRequest.self, from: data) == request)
            let json = String(decoding: data, as: UTF8.self).lowercased()
            #expect(!json.contains("password") && !json.contains("secret"), "\(json)")
        }
    }

    @Test(arguments: [
        ("Report.pdf", ProtectSpec.Mode.lock(nil), "Report Locked.pdf"),
        ("Report.pdf", .lock(restrictions), "Report Locked.pdf"),
        ("Report.pdf", .changePassword, "Report Locked.pdf"),
        ("Report.pdf", .unlock, "Report Unlocked.pdf"),
        ("Report Locked.pdf", .unlock, "Report Unlocked.pdf"),
        ("Report Unlocked.pdf", .lock(nil), "Report Locked.pdf"),
        ("Report Locked.PDF", .changePassword, "Report Locked.pdf"),
        ("Locked.pdf", .unlock, "Locked Unlocked.pdf"),
    ])
    func namesSayWhatHappenedAndReplaceTheOtherSuffix(source: String, mode: ProtectSpec.Mode, expected: String) {
        #expect(OutputNamer().protect(source: source, mode: mode).rendered() == expected)
    }

    @Test func aTakenNameGetsTheCounter() throws {
        let name = OutputNamer().protect(source: "Report.pdf", mode: .unlock)
        let existing: Set<String> = ["Report Unlocked.pdf", "Report Unlocked 2.pdf"]
        #expect(try OutputNamer.nextFree(name, existing: existing, caseInsensitive: true) == "Report Unlocked 3.pdf")
    }

    @Test func theRequestNamesItsOwnOutput() throws {
        let namer = OutputNamer()
        #expect(namer.output(for: try Self.request(.pdf, ProtectSpec(mode: .unlock))).rendered() == "Report Unlocked.pdf")
        let convert = try JobRequest(
            input: try InputItem(url: URL(fileURLWithPath: "/a/photo.heic"), format: .heic, byteCount: 3),
            operation: .convert(.jpg), destination: URL(fileURLWithPath: "/a"))
        #expect(namer.output(for: convert).rendered() == "photo.jpg")
    }
}
