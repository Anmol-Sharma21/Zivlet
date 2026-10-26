import Foundation
import Testing

@testable import ZivletCore

/// Every default wheel list fits the 12 slots. Set `ZIVLET_CAP_COUNTS` to a file path to keep the count lines.
@Suite("Catalog cap lint (P2-100, FR-27, FR-90)")
struct CatalogCapLintTests {
    @Test func noDefaultListIsLongerThanTwelve() throws {
        let over = CatalogLists.standard.all.filter(\.isOverCap)
        #expect(over.isEmpty, "over the cap: \(over.map(\.overCapDescription))")
        if let path = ProcessInfo.processInfo.environment["ZIVLET_CAP_COUNTS"] {
            try CatalogLists.standard.report.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @Test func aThirteenthVisibleToolIsReported() {
        let lists = CatalogLists(tools: .withVisibleTools(13, for: .png), conversions: .standard)
        let png = lists.all.first { $0.name == "png single tools" }
        #expect(png?.count == 13)
        #expect(png?.isOverCap == true)
        #expect(png?.overCapDescription == "png single tools 13 > 12")
    }

    @Test func theStandardListsCoverToolsConversionsAndActions() {
        let names = Set(CatalogLists.standard.all.map(\.name))
        let expected: Set<String> = [
            "png single tools", "png multi tools", "mp4 single tools", "pdf multi tools", "png conversions",
            "docx conversions", "actions",
        ]
        #expect(expected.isSubset(of: names))
        #expect(!names.contains("ogg single tools"), "empty lists are left out")
    }

    @Test func theCountLinesNameEachListAndItsShare() {
        let lines = CatalogLists.standard.report.split(separator: "\n")
        #expect(lines.contains("png single tools 7/12"))
        #expect(lines.contains("mov single tools 10/12 (1 reserved)"))
        #expect(lines.contains("actions 6/12"))
        #expect(lines.count == CatalogLists.standard.all.count)
    }

    /// 05b P2-100: TRANSCRIBE is reserved in the audio and video lists before it is built.
    @Test func transcribeIsCountedInAudioAndVideoLists() {
        let lists = Dictionary(uniqueKeysWithValues: CatalogLists.standard.all.map { ($0.name, $0) })
        #expect(lists["mp4 single tools"]?.description == "mp4 single tools 10/12 (1 reserved)")
        #expect(lists["mov multi tools"]?.description == "mov multi tools 5/12 (1 reserved)")
        #expect(lists["wav single tools"]?.description == "wav single tools 8/12 (1 reserved)")
        #expect(lists["flac multi tools"]?.reserved == 1)
        #expect(lists["png single tools"]?.reserved == 0)
        #expect(lists["mp4 conversions"]?.reserved == 0)
    }

    @Test func fourReservedSlotsPushVideoSinglePastTheCap() {
        let four = (1...4).map { ReservedSlot(name: "R\($0)", formats: [.mp4], lists: [.single]) }
        let lists = CatalogLists(tools: .standard, conversions: .standard, reserved: four)
        let mp4 = lists.all.first { $0.name == "mp4 single tools" }
        #expect(mp4?.isOverCap == true)
        #expect(mp4?.overCapDescription == "mp4 single tools 13 > 12")
    }

    @Test func aReservedSlotAloneMakesAListCount() {
        let slot = ReservedSlot(name: "R", formats: [.ogg], lists: [.multi])
        let lists = CatalogLists(tools: .standard, conversions: .standard, reserved: [slot])
        #expect(lists.all.contains { $0.name == "ogg multi tools" && $0.count == 1 })
        #expect(!lists.all.contains { $0.name == "ogg single tools" })
    }

    @Test func theCapLivesInTheCore() {
        #expect(WheelLimits.maxSlots == 12)
    }
}
