# 06b — M1 tasks 4–5: conversion/tool/action catalog, OutputNamer

Part of [06-implementation-plan-m1](06-implementation-plan-m1.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 4 — Conversion catalog (275 pairs), 27 tools, 6 actions

| Field | Value |
|---|---|
| Goal | The conversion matrix, tool registry with per-format applicability, and the fixed action list, all as data |
| 05 rows | P0-12, P0-14 (engine routes and phase tags are P0-13, index §2.1) |
| Sources | 03a §3.3 (matrix, petal order, family breakdown), 10 §4.13 (count check), 03a §2.6 (tool tables, multi-file mixing, actions), 03a §4.4 (tool suffixes) |

Two TDD cycles, two commits.

### 4a — Conversion pairs

**Files:** create `Sources/ZivletCore/Catalog/ConversionTable.swift`, `Sources/ZivletCore/Catalog/ConversionCatalog.swift`,
`Tests/ZivletCoreTests/ConversionCatalogTests.swift`.

#### 4a.1 Failing tests first

```swift
import Testing

@testable import ZivletCore

@Suite("Conversion catalog (P0-12, 03a §3.3, 10 §4.13)")
struct ConversionCatalogTests {
    let catalog = ConversionCatalog.standard
    let registry = FormatRegistry.standard

    @Test func has275Pairs() {
        #expect(catalog.pairs.count == 275)
        #expect(Set(catalog.pairs).count == 275)
    }

    @Test(arguments: [
        (FormatCategory.raster, 49), (.svg, 8), (.audio, 56), (.video, 42), (.gif, 6), (.pdf, 9),
        (.document, 65), (.slides, 6), (.spreadsheet, 21), (.subtitle, 4), (.archive, 9),
    ])
    func pairCountPerCategory(category: FormatCategory, expected: Int) {
        #expect(catalog.pairCount(in: category) == expected)
    }

    @Test func everyInputHasARowAndOutputOnlyHasNone() {
        let sources = Set(catalog.pairs.map(\.source))
        #expect(sources.count == 45)
        #expect(sources == Set(registry.formats.filter(\.isInput).map(\.id)))
        #expect(catalog.targets(for: .html).isEmpty)
    }

    @Test func targetsAreExactlyThe39OutputFormats() {
        #expect(catalog.distinctTargets.count == 39)
        #expect(catalog.distinctTargets == Set(registry.formats.filter(\.isOutput).map(\.id)))
    }

    @Test func noSelfPairsAndNoInputOnlyTargets() {
        for pair in catalog.pairs {
            #expect(pair.source != pair.target)
            #expect(registry.format(pair.target).isOutput, "\(pair.target) is input-only")
        }
    }

    @Test func petalOrderMatchesSpecSamples() {
        #expect(catalog.targets(for: .png) == [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf])
        #expect(catalog.targets(for: .wav) == [.mp3, .m4a, .flac, .ogg, .opus, .aiff, .wma])
        #expect(catalog.targets(for: .txt).suffix(2) == [.jpg, .png])
        #expect(catalog.targets(for: .docx).suffix(2) == [.png, .jpg])
        #expect(catalog.targets(for: .rar) == [.zip, .tar, .gz])
    }

    @Test func maxPetalCountIsNine() {
        let maxCount = FormatID.allCases.map { catalog.targets(for: $0).count }.max()
        #expect(maxCount == 9)
    }
}
```

#### 4a.2 Run, expect failure

`swift test --filter ZivletCoreTests` → `error: cannot find 'ConversionCatalog' in scope`.

#### 4a.3 Implement

`ConversionTable.swift` (complete; row order = petal order, 03a §3.3):

```swift
// The 275 conversion pairs (03a §3.3, 06b Task 4a). Row order = petal order.
extension ConversionCatalog {
    static let table: [(FormatID, [FormatID])] = raster + audioVideo + documents + dataFormats

    private static let raster: [(FormatID, [FormatID])] = [
        (.jpg, [.png, .webp, .heic, .tiff, .avif, .bmp, .pdf]),
        (.png, [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf]),
        (.webp, [.jpg, .png, .heic, .tiff, .avif, .bmp, .pdf]),
        (.heic, [.jpg, .png, .webp, .tiff, .avif, .bmp, .pdf]),
        (.tiff, [.jpg, .png, .webp, .heic, .avif, .bmp, .pdf]),
        (.avif, [.jpg, .png, .webp, .heic, .tiff, .bmp, .pdf]),
        (.bmp, [.jpg, .png, .webp, .heic, .tiff, .avif, .pdf]),
        (.svg, [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf]),
    ]
    private static let audioVideo: [(FormatID, [FormatID])] = [
        (.mp3, [.m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]),
        (.m4a, [.mp3, .wav, .flac, .ogg, .opus, .aiff, .wma]),
        (.wav, [.mp3, .m4a, .flac, .ogg, .opus, .aiff, .wma]),
        (.flac, [.mp3, .m4a, .wav, .ogg, .opus, .aiff, .wma]),
        (.ogg, [.mp3, .m4a, .wav, .flac, .opus, .aiff, .wma]),
        (.opus, [.mp3, .m4a, .wav, .flac, .ogg, .aiff, .wma]),
        (.aiff, [.mp3, .m4a, .wav, .flac, .ogg, .opus, .wma]),
        (.wma, [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff]),
        (.mp4, [.mov, .mkv, .webm, .avi, .wmv, .gif, .mp3]),
        (.mov, [.mp4, .mkv, .webm, .avi, .wmv, .gif, .mp3]),
        (.mkv, [.mp4, .mov, .webm, .avi, .wmv, .gif, .mp3]),
        (.webm, [.mp4, .mov, .mkv, .avi, .wmv, .gif, .mp3]),
        (.avi, [.mp4, .mov, .mkv, .webm, .wmv, .gif, .mp3]),
        (.wmv, [.mp4, .mov, .mkv, .webm, .avi, .gif, .mp3]),
        (.gif, [.mp4, .mov, .mkv, .webm, .avi, .wmv]),
    ]
    private static let documents: [(FormatID, [FormatID])] = [
        (.pdf, [.docx, .pages, .pptx, .xlsx, .jpg, .png, .epub, .txt, .md]),
        (.docx, [.pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        (.pages, [.docx, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        (.md, [.docx, .pages, .pdf, .txt, .html, .epub, .png, .jpg]),
        (.rtf, [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        (.rtfd, [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        (.textClipping, [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        (.txt, [.docx, .pages, .pdf, .md, .html, .epub, .jpg, .png]),
        (.epub, [.pdf, .docx, .pages, .txt, .md, .html]),
        (.ppt, [.pdf, .jpg, .png]),
        (.pptx, [.pdf, .jpg, .png]),
    ]
    private static let dataFormats: [(FormatID, [FormatID])] = [
        (.xlsx, [.ods, .csv, .tsv, .pdf]),
        (.xls, [.xlsx, .ods, .csv, .tsv, .pdf]),
        (.ods, [.xlsx, .csv, .tsv, .pdf]),
        (.csv, [.xlsx, .ods, .tsv, .pdf]),
        (.tsv, [.xlsx, .ods, .csv, .pdf]),
        (.srt, [.vtt, .txt]),
        (.vtt, [.srt, .txt]),
        (.zip, [.tar, .gz]),
        (.tar, [.zip, .gz]),
        (.gz, [.zip, .tar]),
        (.rar, [.zip, .tar, .gz]),
    ]
}
```

`ConversionCatalog.swift` — outline:

```swift
public struct ConversionPair: Sendable, Hashable, Codable { public let source: FormatID; public let target: FormatID }

public struct ConversionCatalog: Sendable {
    public static let standard = ConversionCatalog(rows: table, registry: .standard)
    public let pairs: [ConversionPair]                         // rows flattened in order
    public func targets(for source: FormatID) -> [FormatID]    // [] for html
    public func canConvert(_ source: FormatID, to target: FormatID) -> Bool
    public func pairCount(in category: FormatCategory) -> Int  // category of the SOURCE format
    public var distinctTargets: Set<FormatID> { get }
}
```

[review] Post-M1 review: rows are `ConversionRow(source, targets)` instead of an unlabeled tuple, and
`ConversionCatalog.init(rows:registry:)` is `throws(CatalogError)` (`selfTarget`, `duplicateRow`, `duplicateTarget`)
instead of a `precondition`. `.standard` uses a private validated init; the table is re-checked by
`CatalogValidationTests`.

#### 4a.4 Verify green

`swift test --filter ZivletCoreTests` → `✔ Test run with 15 tests in 2 suites passed`. The per-category test pins
raster 49, SVG 8, audio 56, video 42, GIF 6, PDF 9, documents 65, slides 6, spreadsheets 21, subtitles 4, archives 9.

#### 4a.5 Commit

```bash
git add Packages/ZivletKit
git commit -s -m "feat(core): add 275-pair conversion catalog in petal order"
```

### 4b — Tools and actions

**Files:** create `Sources/ZivletCore/Catalog/ToolSpec.swift`, `Sources/ZivletCore/Catalog/ToolTable.swift`,
`Sources/ZivletCore/Catalog/ToolCatalog.swift`, `Sources/ZivletCore/Catalog/ActionID.swift`,
`Sources/ZivletCore/Shared/Array+Uniqued.swift`, `Tests/ZivletCoreTests/ToolCatalogTests.swift`.

#### 4b.1 Failing tests first

```swift
import Testing

@testable import ZivletCore

@Suite("Tools and actions catalog (P0-14, 03a §2.6)")
struct ToolCatalogTests {
    let tools = ToolCatalog.standard

    @Test func has27ToolsInCanonicalOrderEndingWithReadQR() {
        let wheelOrder: [ToolID] = [
            .shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop, .audioNormalize,
            .videoMute, .videoTrim, .pdfSplit, .pdfArrange, .archiveUnpack, .pdfFromImages, .pdfCombine,
            .videoCrop, .videoSpeed, .videoJoin, .videoFrameGrab, .videoClips, .audioWaveform,
            .audioTrim, .audioChannelMix, .imageCollage, .imageRedact, .videoRedact, .audioBleep, .qrScan,
        ]
        #expect(ToolID.allCases.count == 27)
        #expect(tools.specs.map(\.id) == wheelOrder)
        #expect(Set(wheelOrder) == Set(ToolID.allCases))
        #expect(tools.specs.last?.wheelLabel == "READ QR")
    }

    @Test func instantToolsAreTheFiveWindowlessOnes() {
        let instant = Set(tools.specs.filter { $0.presentation == .instant }.map(\.id))
        #expect(instant == [.videoMute, .pdfSplit, .archiveUnpack, .pdfFromImages, .qrScan])
    }

    @Test func multiOnlyToolsAreTheFourCombiningOnes() {
        let multiOnly = Set(tools.specs.filter { $0.cardinality == .multiOnly }.map(\.id))
        #expect(multiOnly == [.pdfFromImages, .pdfCombine, .videoJoin, .imageCollage])
    }

    @Test func multiFileListsOnlyContainMultiCapableTools() {
        for row in ToolCatalog.applicability {
            for tool in row.multi { #expect(tools.spec(tool).cardinality != .single, "\(tool)") }
            for tool in row.single { #expect(tools.spec(tool).cardinality != .multiOnly, "\(tool)") }
        }
    }

    @Test(arguments: [
        (
            [FormatID.jpg],
            [
                ToolID.shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop,
                .imageRedact,
            ]
        ),
        ([.jpg, .jpg], [.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        ([.svg], [.qrScan]),
        ([.svg, .svg], [.pdfFromImages, .imageCollage, .qrScan]),
        ([.avif], [.qrScan]),
        ([.pdf], [.shrink, .stripMetadata, .pdfSplit, .pdfArrange, .qrScan]),
        ([.pdf, .pdf], [.shrink, .stripMetadata, .pdfSplit, .pdfCombine, .qrScan]),
        (
            [.wav],
            [
                .shrink, .stripMetadata, .audioNormalize, .audioWaveform, .audioTrim, .audioChannelMix,
                .audioBleep,
            ]
        ),
        ([.flac, .flac], [.shrink, .stripMetadata, .audioNormalize]),
        (
            [.mov],
            [
                .shrink, .stripMetadata, .videoMute, .videoTrim, .videoCrop, .videoSpeed,
                .videoFrameGrab, .videoClips, .videoRedact,
            ]
        ),
        ([.mp4, .mp4], [.shrink, .stripMetadata, .videoMute, .videoJoin]),
        ([.gif], [.stripMetadata, .qrScan]),
        ([.rar], [.archiveUnpack]),
        ([.ogg], []), ([.webm], []), ([.docx], []), ([.xlsx], []), ([.srt], []),
    ])
    func perFormatToolLists(formats: [FormatID], expected: [ToolID]) {
        #expect(tools.tools(for: formats) == expected)
    }

    @Test(arguments: [
        ([FormatID.jpg, .png], [ToolID.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        ([.jpg, .avif], [.qrScan]),
        ([.jpg, .pdf], [.qrScan]),
        ([.gif, .png], [.qrScan]),
        ([.jpg, .mp4], []),
        ([.mp4, .webm], []),
        ([.gif, .mov], [.stripMetadata]),
        ([.zip, .rar, .tar], [.archiveUnpack]),
        ([], []),
    ])
    func mixedSelections(formats: [FormatID], expected: [ToolID]) {
        #expect(tools.tools(for: formats) == expected)
    }

    @Test func actionsAreSixInFixedOrder() {
        #expect(ActionID.allCases.map(\.wheelLabel) == ["AIRDROP", "FLOAT", "COPY", "MOVE", "COPY PATH", "TERMINAL"])
    }
}
```

#### 4b.2 Run, expect failure

`swift test --filter ZivletCoreTests` → `error: cannot find 'ToolCatalog' in scope` (and `ToolID`, `ActionID`).

#### 4b.3 Implement

`ToolSpec.swift` (complete):

```swift
/// The 27 tools, grouped by domain. Zivlet's own identifiers; the wheel order is data (`ToolCatalog.specTable`).
/// [review] Identifiers renamed to Zivlet's own naming scheme (clean-room fix).
public enum ToolID: String, CaseIterable, Codable, Sendable {
    case shrink, stripMetadata
    case imageAdjust, imageMarkup, imageBackdrop, imageCrop, imageCollage, imageRedact
    case pdfSplit, pdfArrange, pdfFromImages, pdfCombine
    case archiveUnpack
    case audioNormalize, audioWaveform, audioTrim, audioChannelMix, audioBleep
    case videoMute, videoTrim, videoCrop, videoSpeed, videoJoin, videoFrameGrab, videoClips, videoRedact
    case qrScan
}

public enum ToolPresentation: String, Codable, Sendable { case instant, editor }

/// `.multiAllowed` = 1…n files; `.multiOnly` = combining tools that need ≥ 2.
public enum ToolCardinality: String, Codable, Sendable { case single, multiAllowed, multiOnly }

public struct ToolSpec: Sendable, Hashable, Codable {
    public let id: ToolID
    public let wheelLabel: String
    public let symbolName: String  // chosen by Zivlet
    public let presentation: ToolPresentation
    public let cardinality: ToolCardinality
    public let outputSuffix: String?  // default suffix; OutputNamer applies variants (03a §4.4)
}
```

`ToolTable.swift` (complete data). Applicability rows are the per-format lists after the multi-file filter
(03a §2.6 table). Suffixes follow the 03a §4.4 suffix table (15 C-19); `OutputNamer` (Task 5)
applies the variants. Symbol names are our own choice.

```swift
// Tool data (06b Task 4b, 03a §4.4). Symbol names are Zivlet's own choice.
extension ToolCatalog {
    struct ApplicabilityRow: Sendable {
        let formats: Set<FormatID>
        let single: [ToolID]
        let multi: [ToolID]
    }

    static let applicability: [ApplicabilityRow] = [
        .init(
            formats: [.jpg, .png, .webp, .heic, .tiff],
            single: [.shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop, .imageRedact],
            multi: [.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        .init(formats: [.svg], single: [.qrScan], multi: [.pdfFromImages, .imageCollage, .qrScan]),
        .init(formats: [.avif, .bmp], single: [.qrScan], multi: [.qrScan]),
        .init(
            formats: [.pdf], single: [.shrink, .stripMetadata, .pdfSplit, .pdfArrange, .qrScan],
            multi: [.shrink, .stripMetadata, .pdfSplit, .pdfCombine, .qrScan]),
        .init(
            formats: [.mp3, .m4a, .wav, .flac],
            single: [
                .shrink, .stripMetadata, .audioNormalize, .audioWaveform, .audioTrim, .audioChannelMix,
                .audioBleep,
            ],
            multi: [.shrink, .stripMetadata, .audioNormalize]),
        .init(
            formats: [.mp4, .mov, .mkv],
            single: [
                .shrink, .stripMetadata, .videoMute, .videoTrim, .videoCrop, .videoSpeed,
                .videoFrameGrab, .videoClips, .videoRedact,
            ],
            multi: [.shrink, .stripMetadata, .videoMute, .videoJoin]),
        .init(formats: [.gif], single: [.stripMetadata, .qrScan], multi: [.stripMetadata, .qrScan]),
        .init(formats: [.zip, .tar, .gz, .rar], single: [.archiveUnpack], multi: [.archiveUnpack]),
    ]

    static let specTable: [ToolSpec] = [
        spec(.shrink, "COMPRESS", "arrow.down.forward.and.arrow.up.backward", .editor, .multiAllowed, "Compressed"),
        spec(.stripMetadata, "METADATA", "tag", .editor, .multiAllowed, "No Metadata"),
        spec(.imageAdjust, "EDIT", "slider.horizontal.3", .editor, .single, "Edited"),
        spec(.imageMarkup, "ANNOTATE", "pencil.tip.crop.circle", .editor, .single, "Annotated"),
        spec(.imageBackdrop, "ADD BG", "square.on.square.dashed", .editor, .single, "With Background"),
        spec(.imageCrop, "CROP", "crop", .editor, .multiAllowed, "Cropped"),
        spec(.audioNormalize, "NORMALIZE", "speaker.wave.2", .editor, .multiAllowed, "Normalized"),
        spec(.videoMute, "MUTE", "speaker.slash", .instant, .multiAllowed, "Muted"),
        spec(.videoTrim, "TRIM", "timeline.selection", .editor, .single, "Trimmed"),
        spec(.pdfSplit, "SPLIT", "doc.on.doc", .instant, .multiAllowed, "Pages"),
        spec(.pdfArrange, "ORGANIZE", "rectangle.grid.2x2", .editor, .single, "Organized"),
        spec(.archiveUnpack, "EXTRACT", "shippingbox", .instant, .multiAllowed, "Extracted"),
        spec(.pdfFromImages, "CREATE PDF", "doc.badge.plus", .instant, .multiOnly, "Images"),
        spec(.pdfCombine, "MERGE PDF", "doc.on.clipboard", .editor, .multiOnly, "Merged"),
        spec(.videoCrop, "CROP", "crop", .editor, .single, "Cropped"),
        spec(.videoSpeed, "SPEED", "gauge.with.dots.needle.67percent", .editor, .single, "Speed"),
        spec(.videoJoin, "JOIN", "film.stack", .editor, .multiOnly, "Joined"),
        spec(.videoFrameGrab, "SNAPSHOT", "camera.viewfinder", .editor, .single, "Snapshot"),
        spec(.videoClips, "SPLIT", "scissors", .editor, .single, "Clips"),
        spec(.audioWaveform, "VISUALIZE", "waveform.path", .editor, .single, "Visualizer"),
        spec(.audioTrim, "TRIM", "timeline.selection", .editor, .single, "Trimmed"),
        spec(.audioChannelMix, "CHANNELS", "speaker.wave.2.circle", .editor, .single, "Mono"),
        spec(.imageCollage, "COLLAGE", "square.grid.3x2", .editor, .multiOnly, "Collage"),
        spec(.imageRedact, "REDACT", "eye.slash", .editor, .single, "Redacted"),
        spec(.videoRedact, "REDACT", "eye.slash", .editor, .single, "Redacted"),
        spec(.audioBleep, "BLEEP", "waveform.badge.minus", .editor, .single, "Bleeped"),
        spec(.qrScan, "READ QR", "qrcode.viewfinder", .instant, .multiAllowed, nil),
    ]

    private static func spec(
        _ id: ToolID, _ label: String, _ symbol: String, _ presentation: ToolPresentation,
        _ cardinality: ToolCardinality, _ suffix: String?
    ) -> ToolSpec {
        ToolSpec(
            id: id, wheelLabel: label, symbolName: symbol, presentation: presentation,
            cardinality: cardinality, outputSuffix: suffix)
    }
}
```

`ToolCatalog.swift` — the selection rule (03a §2.6) in full, the rest as signatures:

```swift
public struct ToolCatalog: Sendable {
    public static let standard = ToolCatalog(registry: .standard)
    public let specs: [ToolSpec]                               // = specTable, canonical order
    public func spec(_ id: ToolID) -> ToolSpec

    /// One FormatID per selected item; the item count is formats.count.
    public func tools(for formats: [FormatID]) -> [ToolID] {
        guard let first = formats.first else { return [] }
        let distinct = formats.uniqued()
        let count = formats.count
        if distinct.count == 1 { return tools(for: first, count: count) }
        let shared = sharedTools(distinct, count: count)       // same family → intersection, first format's order
        if !shared.isEmpty { return shared }
        return distinct.allSatisfy(qualifiesForReadQR) ? [.qrScan] : []   // image family, gif or pdf
    }
    func tools(for format: FormatID, count: Int) -> [ToolID]   // row.multi when count >= 2, else row.single
}
```

`ActionID.swift`: `enum ActionID: String, CaseIterable, Codable, Sendable { case shareAirDrop, pinFloating, copyTo, moveTo,
copyFilePath, openInTerminal }` with `wheelLabel` (`AIRDROP`, `FLOAT`, `COPY`, `MOVE`, `COPY PATH`, `TERMINAL`) and our own `symbolName`.

`Array+Uniqued.swift` (complete; reused by Task 7):

```swift
extension Array where Element: Hashable {
    /// First occurrence of each element, order kept.
    public func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
```

#### 4b.4 Verify green

`swift test --filter ZivletCoreTests` → `✔ Test run with 22 tests in 3 suites passed`.

#### 4b.5 Commit

```bash
git add Packages/ZivletKit
git commit -s -m "feat(core): add 27-tool registry with per-format applicability and 6 actions"
```

---

## Task 5 — OutputNamer

| Field | Value |
|---|---|
| Goal | Pure naming: conversion names, tool suffixes and variants, folder outputs and items, collision counters, NFC, 255-byte limit |
| 05 row | P0-16 |
| Sources | 03a §4.4 (rules, suffix table, base name, collisions, folder items), 03a §4.3 (9,999 cap), 15 C-19 (parity names are the default) |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletCore/Naming/OutputName.swift` |
| create | `Sources/ZivletCore/Naming/OutputNamer.swift` — base name, conversion, folders, items |
| create | `Sources/ZivletCore/Naming/OutputNamer+Tools.swift` — tool suffixes and extensions |
| create | `Sources/ZivletCore/Naming/OutputNamer+Collisions.swift` — `nextFree` |
| create | `Tests/ZivletCoreTests/OutputNamerTests.swift` |

### 5.1 Failing tests first

```swift
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

    @Test func throwsAfterCandidateCap() {
        let name = OutputName(stem: "a", ext: "jpg")
        let taken = Set(["a.jpg"] + (2...OutputNamer.maxCandidates).map { "a \($0).jpg" })
        #expect(throws: NamingError.noFreeName("a.jpg")) {
            try OutputNamer.nextFree(name, existing: taken, caseInsensitive: true)
        }
    }

    @Test func longNamesAreTruncatedToUTF8LimitWithoutSplittingGraphemes() {
        let stem = String(repeating: "👩‍👩‍👧", count: 40)  // 18 UTF-8 bytes per grapheme
        let rendered = OutputName(stem: stem, ext: "jpg").rendered(counter: 12)
        #expect(rendered.utf8.count <= 255)
        #expect(rendered.hasSuffix(" 12.jpg"))
        #expect(rendered.dropLast(" 12.jpg".count).allSatisfy { $0 == "👩‍👩‍👧" })
    }

    @Test func namesAreNFC() {
        let decomposed = "Cafe\u{301}"
        #expect(OutputName(stem: decomposed, ext: "png").rendered() == "Caf\u{E9}.png")
    }

    @Test func folderItemsArePadded() {
        #expect(namer.folderItem(prefix: "Page", index: 1, count: 12, ext: "png") == "Page 001.png")
        #expect(namer.folderItem(prefix: "Clip", index: 42, count: 1_200, ext: "mp4") == "Clip 0042.mp4")
        #expect(namer.snapshotItem(index: 1, count: 3, seconds: 12.345) == "Frame 001 - 12.345s.png")
        #expect(namer.pagesFolder(source: "report.pdf", target: .png).rendered() == "report PNG Pages")
    }
}
```

### 5.2 Run, expect failure

`swift test --filter ZivletCoreTests` → `error: cannot find 'OutputNamer' in scope` (and `OutputName`, `NamingError`).

### 5.3 Implement

`OutputName.swift` (complete; the truncation loop is the subtle part):

```swift
import Foundation

/// A proposed output name before collision handling. `ext == nil` means a folder.
public struct OutputName: Sendable, Hashable, Codable {
    public static let maxBytes = 255

    public let stem: String
    public let ext: String?

    public init(stem: String, ext: String?) {
        self.stem = stem.precomposedStringWithCanonicalMapping
        self.ext = ext
    }

    public var isFolder: Bool { ext == nil }

    /// `counter` 2, 3, … appends " 2" before the extension (03a §4.4). Stem is truncated grapheme-safely
    /// so the UTF-8 name never exceeds 255 bytes.
    public func rendered(counter: Int? = nil) -> String {
        let tail = (counter.map { " \($0)" } ?? "") + (ext.map { ".\($0)" } ?? "")
        var stem = self.stem
        while !stem.isEmpty, (stem + tail).utf8.count > Self.maxBytes { stem.removeLast() }
        return stem + tail
    }
}
```

`OutputNamer.swift` — outline:

```swift
public enum NamingError: Error, Equatable, Sendable { case noFreeName(String) }
public enum MetadataNaming: Sendable, Equatable { case removeAll, edit }
public enum ChannelNaming: String, Sendable, Equatable { case mono = "Mono", stereo = "Stereo" }

public struct OutputNamer: Sendable {
    public static let maxCandidates = 9_999
    static let compoundExtensions = ["tar.gz", "tgz", "tar.xz", "tar.bz2", "tar.zst"]
    let registry: FormatRegistry
    public init(registry: FormatRegistry = .standard)
    public func baseName(of fileName: String) -> String                        // compound ext as one unit, else FileNameParts.stem
    public func conversion(source fileName: String, target: FormatID) -> OutputName       // ext = canonicalExtension
    public func pagesFolder(source fileName: String, target: FormatID) -> OutputName      // "<base> <LABEL> Pages", ext nil
    public func folderItem(prefix: String, index: Int, count: Int, ext: String) -> String // "Page 001.png"
    public func snapshotItem(index: Int, count: Int, seconds: Double) -> String           // "Frame 001 - 12.345s.png"
    static func padded(_ index: Int, count: Int) -> String                    // width max(3, digits(count))
}
```

`baseName`: if the lower-cased name ends with `"." + compound` and the remainder is non-empty, drop it; otherwise
`FileNameParts(fileName).stem` (`.tar.gz` alone → `.tar`). `snapshotItem` formats seconds with `String(format: "%.3f")`.

`OutputNamer+Tools.swift` — `ToolNaming` (all `let`, defaults `metadata .removeAll`, `speed 2.0`, `channels .mono`,
`snapshotCount 1`) and `tool(_:source:format:naming:) -> OutputName?` = `"<base> <suffix>"` + extension:

| Tool | Suffix rule | Extension rule |
|---|---|---|
| stripMetadata on an image-family format | `Metadata Removed` (`.removeAll`) / `Metadata Edited` (`.edit`) | same |
| stripMetadata on PDF, audio, video | spec suffix `No Metadata` | same |
| videoSpeed | `"Speed \(speed.description)x"` → `Speed 2.0x`, `Speed 0.5x` | same |
| audioChannelMix | `Mono` / `Stereo` | same |
| videoFrameGrab | `Snapshot`; `Snapshots` when `snapshotCount > 1` | `png`; folder (nil) when several |
| shrink | `Compressed` | `flac` for wav and aiff, else same |
| imageMarkup, imageCollage | `Annotated`, `Collage` | `png` |
| videoClips, pdfSplit, archiveUnpack | `Clips`, `Pages`, `Extracted` | folder (nil) |
| pdfFromImages, pdfCombine | `Images`, `Merged` | `pdf` |
| videoJoin, audioWaveform | `Joined`, `Visualizer` | `mp4` |
| qrScan | no output → `nil` | — |
| every other tool | `ToolSpec.outputSuffix` | same (`canonicalExtension` of the source) |

Each column is one `switch` in its own function (`suffix(_:format:naming:)`, `outputExtension(_:format:naming:)`), each
under 20 lines. Multi-input tools pass the first file as `source`.

`OutputNamer+Collisions.swift` (complete):

```swift
import Foundation

extension OutputNamer {
    /// First free rendering of `name`: `name`, `name 2`, `name 3`, … (cap 9,999, 03a §4.3).
    public static func nextFree(
        _ name: OutputName, existing: Set<String>,
        caseInsensitive: Bool
    ) throws(NamingError) -> String {
        let taken = Set(existing.map { key($0, caseInsensitive: caseInsensitive) })
        let first = name.rendered()
        if !taken.contains(key(first, caseInsensitive: caseInsensitive)) { return first }
        for counter in 2...maxCandidates {
            let candidate = name.rendered(counter: counter)
            if !taken.contains(key(candidate, caseInsensitive: caseInsensitive)) { return candidate }
        }
        throw .noFreeName(first)
    }

    static func key(_ name: String, caseInsensitive: Bool) -> String {
        let nfc = name.precomposedStringWithCanonicalMapping
        return caseInsensitive ? nfc.lowercased() : nfc
    }
}
```

[review] `OutputNamer.init(registry:tools:)` also injects the `ToolCatalog` (default `.standard`); `suffix` no longer
reads `ToolCatalog.standard`.

[review] Output names are sanitised to one path component (`FileNameRules.safeStem`): `OutputName.init(stem:ext:)` is
`throws(NamingError)` (`invalidExtension`), the namer uses an internal `init(stem:validExtension:)` for format
extensions and literals, and `folderItem` now throws. Tests: `OutputNameSafetyTests`.

### 5.4 Verify green

`swift test --filter ZivletCoreTests` → `✔ Test run with 33 tests in 4 suites passed`.

### 5.5 Commit

```bash
git add Packages/ZivletKit
git commit -s -m "feat(core): add OutputNamer with tool suffixes, collisions and length limits"
```
