import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Hub label and byte sizes (03a §2.6)")
struct HubLabelTests {
    func file(_ name: String, _ format: FormatID?, _ bytes: Int64? = 1_000) -> HubItem {
        HubItem(name: name, format: format, kind: .file, byteCount: bytes)
    }
    func folder(_ name: String) -> HubItem { HubItem(name: name, format: nil, kind: .folder, byteCount: nil) }

    @Test func oneFileShowsNameAndSize() {
        #expect(HubLabel.text(for: [file("Sunset.heic", .heic, 2_240_000)]) == "Sunset.heic\n2.2 MB")
        #expect(HubLabel.text(for: [file("Sunset.heic", .heic, nil)]) == "Sunset.heic")
    }

    @Test func severalFilesOfOneTypeShowCountTypeAndTotal() {
        let items = [file("a.png", .png, 30_000_000), file("b.png", .png, 18_000_000)]
        #expect(HubLabel.text(for: items) == "2 PNG FILES\n48 MB")
        #expect(HubLabel.text(for: [file("a.gz", .gz), file("b.gz", .gz)]) == "2 GZIP FILES\n2.0 KB")
    }

    @Test func mixedFilesFoldersAndEmpty() {
        #expect(HubLabel.text(for: [file("a.png", .png), file("b.mov", .mov)]) == "MIXED\n2.0 KB")
        #expect(HubLabel.text(for: [file("a.png", .png), file("x", nil)]) == "MIXED\n2.0 KB")
        #expect(HubLabel.text(for: [folder("Photos")]) == "FOLDER")
        #expect(HubLabel.text(for: [folder("A"), folder("B"), folder("C")]) == "3 FOLDERS")
        #expect(HubLabel.text(for: [folder("A"), file("a.png", .png)]) == "2 ITEMS")
        #expect(HubLabel.text(for: []) == "")
    }

    @Test func unknownSizeDropsTheSizeLine() {
        #expect(HubLabel.text(for: [file("a.png", .png), file("b.png", .png, nil)]) == "2 PNG FILES")
    }

    /// 03a §2.2: compact (7 pt semibold) means more than one source item, whatever the text says.
    @Test func compactStyleFollowsTheItemCountNotTheText() {
        #expect(!HubLabel.isCompact(for: [file("Sunset.heic", .heic, 2_240_000)]))
        #expect(!HubLabel.isCompact(for: [folder("Photos")]))
        #expect(!HubLabel.isCompact(for: []))
        #expect(HubLabel.isCompact(for: [file("a.png", .png), file("b.png", .png, nil)]))
        #expect(HubLabel.isCompact(for: [folder("A"), folder("B")]))
    }

    @Test(arguments: [
        (Int64(0), "Zero bytes"), (1, "1 byte"), (999, "999 bytes"), (1_000, "1.0 KB"), (2_240_000, "2.2 MB"),
        (48_000_000, "48 MB"), (999_449, "999 KB"), (999_500, "1.0 MB"), (9_960_000, "10 MB"),
        (5_000_000_000_000, "5.0 TB"), (12_000_000_000_000_000, "12000 TB"),
    ])
    func byteSizesUseDecimalUnits(bytes: Int64, text: String) {
        #expect(ByteSize.text(bytes) == text)
    }
}
