import Testing

@testable import ZivletCore

@Suite("OutputNamer (P0-16, 03a §4.4)")
struct OutputNamerTests {
    let namer = OutputNamer()

    @Test(arguments: [
        ("photo.jpg", "photo"), ("a.tar.gz", "a"), ("b.TGZ", "b"), ("c.tar.xz", "c"), ("d.tar.bz2", "d"),
        ("e.tar.zst", "e"), ("my.photo.final.png", "my.photo.final"), (".hidden", ".hidden"), ("noext", "noext"),
        ("x.gz", "x"), ("trailing.", "trailing."), (".tar.gz", ".tar"),
    ])
    func baseNameStripsCompoundExtensionsAsOneUnit(name: String, expected: String) {
        #expect(namer.baseName(of: name) == expected)
    }

    @Test(arguments: [
        ("IMG_1.HEIC", FormatID.jpg, "IMG_1.jpg"), ("a.png", .webp, "a.webp"), ("song.wav", .mp3, "song.mp3"),
        ("dir.zip", .gz, "dir.tar.gz"), ("x.tar", .gz, "x.tar.gz"), ("x.tar.gz", .zip, "x.zip"),
        ("Clip.MOV", .mp4, "Clip.mp4"), ("page.md", .html, "page.html"), ("a.tiff", .heic, "a.heic"),
    ])
    func conversionUsesCanonicalLowercaseExtension(source: String, target: FormatID, expected: String) {
        #expect(namer.conversion(source: source, target: target).rendered() == expected)
    }

    @Test(arguments: [
        (ToolID.shrink, "a.jpg", FormatID.jpg, "a Compressed.jpg"),
        (.shrink, "voice.wav", .wav, "voice Compressed.flac"),
        (.shrink, "take.aiff", .aiff, "take Compressed.flac"),
        (.shrink, "song.mp3", .mp3, "song Compressed.mp3"),
        (.stripMetadata, "a.png", .png, "a Metadata Removed.png"),
        (.stripMetadata, "doc.pdf", .pdf, "doc No Metadata.pdf"),
        (.stripMetadata, "clip.mov", .mov, "clip No Metadata.mov"),
        (.imageMarkup, "a.jpg", .jpg, "a Annotated.png"),
        (.imageBackdrop, "a.heic", .heic, "a With Background.heic"),
        (.videoCrop, "geese.mp4", .mp4, "geese Cropped.mp4"),
        (.videoMute, "v.mkv", .mkv, "v Muted.mkv"),
        (.audioBleep, "s.m4a", .m4a, "s Bleeped.m4a"),
        (.videoSpeed, "v.mp4", .mp4, "v Speed 2.0x.mp4"),
        (.videoFrameGrab, "v.mov", .mov, "v Snapshot.png"),
        (.audioWaveform, "s.flac", .flac, "s Visualizer.mp4"),
        (.audioChannelMix, "s.wav", .wav, "s Mono.wav"),
        (.pdfFromImages, "first.jpg", .jpg, "first Images.pdf"),
        (.pdfCombine, "first.pdf", .pdf, "first Merged.pdf"),
        (.videoJoin, "first.mov", .mov, "first Joined.mp4"),
        (.imageCollage, "first.png", .png, "first Collage.png"),
        (.pdfArrange, "d.pdf", .pdf, "d Organized.pdf"),
        (.videoClips, "v.mp4", .mp4, "v Clips"),
        (.pdfSplit, "d.pdf", .pdf, "d Pages"),
        (.archiveUnpack, "a.tar.gz", .gz, "a Extracted"),
    ])
    func toolNames(tool: ToolID, source: String, format: FormatID, expected: String) throws {
        let name = try #require(namer.tool(tool, source: source, format: format))
        #expect(name.rendered() == expected)
    }

    @Test func toolVariants() throws {
        let naming = OutputNamer.ToolNaming(metadata: .edit, speed: 0.5, channels: .stereo, snapshotCount: 3)
        #expect(
            try #require(namer.tool(.stripMetadata, source: "a.jpg", format: .jpg, naming: naming)).rendered()
                == "a Metadata Edited.jpg")
        #expect(
            try #require(namer.tool(.videoSpeed, source: "v.mp4", format: .mp4, naming: naming)).rendered()
                == "v Speed 0.5x.mp4")
        #expect(
            try #require(namer.tool(.audioChannelMix, source: "s.mp3", format: .mp3, naming: naming)).rendered()
                == "s Stereo.mp3")
        let folder = try #require(namer.tool(.videoFrameGrab, source: "v.mp4", format: .mp4, naming: naming))
        #expect(folder.rendered() == "v Snapshots" && folder.isFolder)
        #expect(namer.tool(.qrScan, source: "a.png", format: .png) == nil)
    }

    @Test func collisionsAppendSpaceAndCounter() throws {
        let name = namer.conversion(source: "a.png", target: .jpg)
        #expect(try OutputNamer.nextFree(name, existing: [], caseInsensitive: true) == "a.jpg")
        #expect(try OutputNamer.nextFree(name, existing: ["a.jpg"], caseInsensitive: true) == "a 2.jpg")
        #expect(try OutputNamer.nextFree(name, existing: ["a.jpg", "a 2.jpg"], caseInsensitive: true) == "a 3.jpg")
    }

    @Test func collisionKeepsCompoundExtensionAndFolderShape() throws {
        let gz = namer.conversion(source: "dir.zip", target: .gz)
        #expect(try OutputNamer.nextFree(gz, existing: ["dir.tar.gz"], caseInsensitive: true) == "dir 2.tar.gz")
        let folder = try #require(namer.tool(.archiveUnpack, source: "a.zip", format: .zip))
        #expect(try OutputNamer.nextFree(folder, existing: ["a Extracted"], caseInsensitive: true) == "a Extracted 2")
    }

    @Test func caseSensitivityFollowsTheVolume() throws {
        let name = namer.conversion(source: "a.png", target: .jpg)
        #expect(try OutputNamer.nextFree(name, existing: ["A.JPG"], caseInsensitive: true) == "a 2.jpg")
        #expect(try OutputNamer.nextFree(name, existing: ["A.JPG"], caseInsensitive: false) == "a.jpg")
    }

    @Test func throwsAfterCandidateCap() throws {
        let name = try OutputName(stem: "a", ext: "jpg")
        let taken = Set(["a.jpg"] + (2...OutputNamer.maxCandidates).map { "a \($0).jpg" })
        #expect(throws: NamingError.noFreeName("a.jpg")) {
            try OutputNamer.nextFree(name, existing: taken, caseInsensitive: true)
        }
    }

    @Test func longNamesAreTruncatedToUTF8LimitWithoutSplittingGraphemes() throws {
        let stem = String(repeating: "👩‍👩‍👧", count: 40)  // 18 UTF-8 bytes per grapheme
        let rendered = try OutputName(stem: stem, ext: "jpg").rendered(counter: 12)
        #expect(rendered.utf8.count <= 255)
        #expect(rendered.hasSuffix(" 12.jpg"))
        #expect(rendered.dropLast(" 12.jpg".count).allSatisfy { $0 == "👩‍👩‍👧" })
    }

    @Test func namesAreNFC() throws {
        let decomposed = "Cafe\u{301}"
        #expect(try OutputName(stem: decomposed, ext: "png").rendered() == "Caf\u{E9}.png")
    }

    @Test func folderItemsArePadded() throws {
        #expect(try namer.folderItem(prefix: "Page", index: 1, count: 12, ext: "png") == "Page 001.png")
        #expect(try namer.folderItem(prefix: "Clip", index: 42, count: 1_200, ext: "mp4") == "Clip 0042.mp4")
        #expect(namer.snapshotItem(index: 1, count: 3, seconds: 12.345) == "Frame 001 - 12.345s.png")
        #expect(namer.pagesFolder(source: "report.pdf", target: .png).rendered() == "report PNG Pages")
    }
}
