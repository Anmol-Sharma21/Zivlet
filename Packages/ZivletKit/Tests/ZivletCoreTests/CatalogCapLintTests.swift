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
        #expect(lines.contains("mov single tools 9/12"))
        #expect(lines.contains("actions 6/12"))
        #expect(lines.count == CatalogLists.standard.all.count)
    }

    @Test func theCapLivesInTheCore() {
        #expect(WheelLimits.maxSlots == 12)
    }
}
