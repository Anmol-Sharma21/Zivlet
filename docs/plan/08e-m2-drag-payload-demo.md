# 08e — M2 task 8: drag payload reader and demo scenario

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 8 — Drag payload reader (per change count) and DEBUG demo scenario (P0-41, P0-43)

| Field | Value |
|---|---|
| Goal | `DragPayloadReader`: when the trigger asks (`probePayload(cc)`), read the drag pasteboard's **file URLs** once on the main actor, classify them off the main actor (`@concurrent`: directory, package, size, local volume; extension → `FormatID`), cache the result by change count, and never let an older count overwrite a newer one. It answers the trigger with a `DragSummary` (item count, accepted modes from `SliceBuilder`) and keeps the full `DragPayload` (URLs, `SelectionItem`s, `HubItem`s) for the wheel. `DemoScenario`: parses `-ZivletDemoWheel convert\|tools\|actions [-ZivletDemoFiles a.png,Photos/] [-ZivletDemoHighlight n]` into a synthetic payload, so the wheel can be shown and screenshotted without a drag |
| 05 rows | P0-41 (payload side), P0-43 (demo); M2 exit "correct slices" |
| Sources | 03a §1.6 (probe: read once per change count, stat off-main, ≤ 512 items stat'ed, extension-only beyond), 03a §2.6 (selection rules, hub label), 03a §1.5 (probe budget), index D-M2-3 |

Classification of one URL:

| Resource values | `SelectionItem` | `HubItem.byteCount` |
|---|---|---|
| regular file | `(format from extension, .file, isLocal: volumeIsLocal ?? true)` | file size |
| directory, not a package | `(nil, .folder)` | nil |
| directory and package (`.pages`, `.rtfd`, `.app`) | `(format or nil, .package)` | nil |
| `resourceValues` throws (missing, unreadable) | `(format, .file, isLocal: false)`: the wheel shows "Zivlet can't read one of these files" | nil |
| index ≥ 512 | `(format, .file)` without a stat | nil |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletWheel/DragPayload.swift` (`DragPayload`, `ClassifiedItem`, `DragPayloadReader`) |
| create | `Sources/ZivletWheel/DemoScenario.swift` (`DemoScenario`, `DemoScenarioError`), whole file and `WheelController.showDemo` under `#if DEBUG` so Release ships neither |
| create | `Tests/ZivletWheelTests/DragPayloadTests.swift` (also `TempItems`, used again in Task 10) |

### 8.1 Failing tests first

Real files in a temporary folder and a uniquely named pasteboard; no mocks.

`Packages/ZivletKit/Tests/ZivletWheelTests/DragPayloadTests.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheelCore
import Testing

@testable import ZivletWheel

/// A temporary folder with a few real items; removed when the test value goes away.
final class TempItems {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "zivlet-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func file(_ name: String, bytes: Int = 1_200) throws -> URL {
        let url = root.appending(path: name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func folder(_ name: String) throws -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite("Drag payload: pasteboard URLs → selection items (03a §1.6)")
struct DragPayloadTests {
    let pasteboard = NSPasteboard.withUniqueName()

    func put(_ urls: [URL]) -> Int {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        return pasteboard.changeCount
    }

    @Test func readsFileURLsOnlyInOrder() throws {
        let temp = try TempItems()
        let a = try temp.file("a.png")
        let b = try temp.file("b.mov")
        let web = try #require(URL(string: "https://example.com"))
        pasteboard.clearContents()
        pasteboard.writeObjects([a as NSURL, web as NSURL, b as NSURL])
        #expect(DragPayloadReader.fileURLs(from: pasteboard) == [a, b])
    }

    @Test func classifiesFilesFoldersPackagesUnknownAndMissing() async throws {
        let temp = try TempItems()
        let urls = [
            try temp.file("photo.png", bytes: 2_000), try temp.folder("Photos"), try temp.folder("Doc.pages"),
            try temp.file("notes.xyz"), temp.root.appending(path: "gone.jpg"),
        ]
        let payload = await DragPayloadReader(pasteboard: pasteboard).read(changeCount: put(urls))
        #expect(
            payload.items == [
                SelectionItem(.png), SelectionItem(nil, kind: .folder), SelectionItem(.pages, kind: .package),
                SelectionItem(nil), SelectionItem(.jpg, isLocal: false),
            ])
        #expect(payload.hubItems.map(\.name) == ["photo.png", "Photos", "Doc.pages", "notes.xyz", "gone.jpg"])
        #expect(payload.hubItems.map(\.byteCount) == [2_000, nil, nil, 1_200, nil])
    }

    @Test func cachesByChangeCountAndIgnoresOlderResults() async throws {
        let temp = try TempItems()
        let reader = DragPayloadReader(pasteboard: pasteboard)
        let first = put([try temp.file("a.png")])
        let payload = await reader.read(changeCount: first)
        let second = put([try temp.file("b.mov")])
        #expect(await reader.read(changeCount: first) == payload)
        let newer = await reader.read(changeCount: second)
        #expect(newer.items == [SelectionItem(.mov)])
        #expect(reader.latest == newer)
    }

    @Test func summaryListsTheModesWithContent() async throws {
        let temp = try TempItems()
        let reader = DragPayloadReader(pasteboard: pasteboard)
        let png = await reader.summary(changeCount: put([try temp.file("a.png")]))
        #expect(png == DragSummary(itemCount: 1, acceptedModes: [.convert, .tools, .actions]))
        let folder = await reader.summary(changeCount: put([try temp.folder("F")]))
        #expect(folder.acceptedModes == [.actions])
    }

    @Test func itemsPastTheStatLimitUseTheExtensionOnly() async {
        let urls = (0...DragPayloadReader.statLimit).map { URL(fileURLWithPath: "/nonexistent/\($0).png") }
        let items = await DragPayloadReader.classify(urls, registry: .standard).map(\.item)
        #expect(items.count == 513)
        #expect(items[0] == SelectionItem(.png, isLocal: false))
        #expect(items[512] == SelectionItem(.png))
    }
}

@Suite("Demo scenario launch arguments (DEBUG wheel without a drag)")
struct DemoScenarioTests {
    @Test func absentFlagMeansNoDemo() throws {
        #expect(try DemoScenario.parse(arguments: ["Zivlet"]) == nil)
    }

    @Test(arguments: WheelMode.allCases)
    func eachModeHasASampleSelection(mode: WheelMode) throws {
        let demo = try #require(try DemoScenario.parse(arguments: ["Zivlet", "-ZivletDemoWheel", mode.rawValue]))
        #expect(demo.mode == mode && demo.highlight == nil)
        #expect(!SliceBuilder().content(for: mode, items: demo.payload.items).slices.isEmpty)
    }

    @Test func sampleMatchesTheParsedDefault() throws {
        let parsed = try DemoScenario.parse(arguments: ["S", "-ZivletDemoWheel", "actions"])
        #expect(DemoScenario.sample(.actions) == parsed)
    }

    @Test func filesAndHighlightAreConfigurable() throws {
        let args = [
            "S", "-ZivletDemoWheel", "convert", "-ZivletDemoFiles", "a.png,b.png", "-ZivletDemoHighlight", "2",
        ]
        let demo = try #require(try DemoScenario.parse(arguments: args))
        #expect(demo.payload.items == [SelectionItem(.png), SelectionItem(.png)])
        #expect(demo.payload.hubItems.map(\.name) == ["a.png", "b.png"])
        #expect(demo.payload.urls.map(\.lastPathComponent) == ["a.png", "b.png"])
        #expect(demo.highlight == 2)
    }

    @Test func folderNamesEndWithASlash() throws {
        let args = ["S", "-ZivletDemoWheel", "actions", "-ZivletDemoFiles", "Photos/"]
        let demo = try #require(try DemoScenario.parse(arguments: args))
        #expect(demo.payload.items == [SelectionItem(nil, kind: .folder)])
        #expect(demo.payload.hubItems.first?.byteCount == nil)
    }

    @Test func badValuesAreTypedErrors() {
        #expect(throws: DemoScenarioError.unknownMode("spin")) {
            try DemoScenario.parse(arguments: ["S", "-ZivletDemoWheel", "spin"])
        }
        #expect(throws: DemoScenarioError.missingValue("-ZivletDemoWheel")) {
            try DemoScenario.parse(arguments: ["S", "-ZivletDemoWheel"])
        }
        #expect(throws: DemoScenarioError.badHighlight("x")) {
            try DemoScenario.parse(arguments: ["S", "-ZivletDemoWheel", "tools", "-ZivletDemoHighlight", "x"])
        }
    }
}
```

### 8.2 Run, expect failure

`swift test --filter ZivletWheelTests` → `error: cannot find 'DragPayloadReader' in scope` (also `DemoScenario`,
`DemoScenarioError`).

### 8.3 Implement (complete)

`statLimit` and `ClassifiedItem` are `nonisolated`, because the module defaults to the main actor and the classifier
runs off it (the compiler reports `main actor-isolated static property 'statLimit' can not be referenced from a
nonisolated context` otherwise).

`Packages/ZivletKit/Sources/ZivletWheel/DragPayload.swift`:

```swift
import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheelCore

/// What is being dragged, read once per drag-pasteboard change count (03a §1.6).
public struct DragPayload: Sendable, Equatable {
    public let changeCount: Int
    public let urls: [URL]
    public let items: [SelectionItem]
    public let hubItems: [HubItem]

    public init(changeCount: Int, urls: [URL], items: [SelectionItem], hubItems: [HubItem]) {
        self.changeCount = changeCount
        self.urls = urls
        self.items = items
        self.hubItems = hubItems
    }

    /// The trigger's view: item count and the modes that have content (`DragSummary.acceptedModes`).
    public func summary(builder: SliceBuilder = SliceBuilder()) -> DragSummary {
        DragSummary(itemCount: items.count, acceptedModes: builder.acceptedModes(items: items))
    }
}

/// One URL after classification.
nonisolated public struct ClassifiedItem: Sendable, Equatable {
    public let item: SelectionItem
    public let hub: HubItem
}

/// Reads file URLs from the drag pasteboard on the main actor, then stats them off it. Results are cached by change
/// count and never replaced by an older count's result.
public final class DragPayloadReader {
    /// Items beyond this are classified by extension only (03a §1.5 probe budget).
    public nonisolated static let statLimit = 512

    public private(set) var latest: DragPayload?
    private let pasteboard: NSPasteboard
    private let registry: FormatRegistry
    private let builder: SliceBuilder

    public init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag), registry: FormatRegistry = .standard,
        builder: SliceBuilder = SliceBuilder()
    ) {
        self.pasteboard = pasteboard
        self.registry = registry
        self.builder = builder
    }

    public func read(changeCount: Int) async -> DragPayload {
        if let latest, latest.changeCount == changeCount { return latest }
        let urls = Self.fileURLs(from: pasteboard)
        let classified = await Self.classify(urls, registry: registry)
        let payload = DragPayload(
            changeCount: changeCount, urls: urls, items: classified.map(\.item), hubItems: classified.map(\.hub))
        if changeCount >= (latest?.changeCount ?? .min) { latest = payload }
        return payload
    }

    /// The trigger host's payload probe.
    public func summary(changeCount: Int) async -> DragSummary {
        await read(changeCount: changeCount).summary(builder: builder)
    }

    /// File URLs only; web links and text on the same pasteboard are ignored.
    public static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objects ?? []).compactMap { $0 as? URL }
    }

    @concurrent
    nonisolated static func classify(_ urls: [URL], registry: FormatRegistry) async -> [ClassifiedItem] {
        urls.enumerated().map { index, url in
            classify(url, stat: index < statLimit, registry: registry)
        }
    }

    private nonisolated static func classify(_ url: URL, stat: Bool, registry: FormatRegistry) -> ClassifiedItem {
        let name = url.lastPathComponent
        let format = registry.formatID(fileName: name)
        guard stat else { return item(format, .file, isLocal: true, bytes: nil, name: name) }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .volumeIsLocalKey]
        do {
            let values = try url.resourceValues(forKeys: keys)
            let kind: SelectionItemKind =
                values.isDirectory == true ? (values.isPackage == true ? .package : .folder) : .file
            let bytes = kind == .file ? values.fileSize.map(Int64.init) : nil
            return item(
                kind == .folder ? nil : format, kind, isLocal: values.volumeIsLocal ?? true, bytes: bytes, name: name)
        } catch {
            // Unreadable or gone: the wheel shows "Zivlet can't read one of these files".
            return item(format, .file, isLocal: false, bytes: nil, name: name)
        }
    }

    private nonisolated static func item(
        _ format: FormatID?, _ kind: SelectionItemKind, isLocal: Bool, bytes: Int64?, name: String
    ) -> ClassifiedItem {
        ClassifiedItem(
            item: SelectionItem(format, kind: kind, isLocal: isLocal),
            hub: HubItem(name: name, format: format, kind: kind, byteCount: bytes))
    }
}
```

Demo payloads use made-up URLs under `/tmp/ZivletDemo/`. They need not exist because the demo never drops. The sample
selections are one HEIC (convert, 7 slices), one MOV (tools, 9 slices) and a PDF plus a folder (actions, 6 slices).

`Packages/ZivletKit/Sources/ZivletWheel/DemoScenario.swift`:

```swift
import Foundation
import ZivletCore
import ZivletWheelCore

public enum DemoScenarioError: Error, Equatable, Sendable {
    case unknownMode(String)
    case missingValue(String)
    case badHighlight(String)
}

/// DEBUG launch arguments that show the wheel at screen centre without a drag, so screenshots can be automated:
/// `-ZivletDemoWheel convert|tools|actions [-ZivletDemoFiles a.png,Photos/] [-ZivletDemoHighlight 2]`.
/// File names need not exist; a trailing "/" makes a folder.
public struct DemoScenario: Sendable, Equatable {
    public static let wheelFlag = "-ZivletDemoWheel"
    public static let filesFlag = "-ZivletDemoFiles"
    public static let highlightFlag = "-ZivletDemoHighlight"
    static let sampleBytes: Int64 = 2_400_000

    public let mode: WheelMode
    public let payload: DragPayload
    public let highlight: Int?

    /// Nil when the wheel flag is absent.
    public static func parse(
        arguments: [String], registry: FormatRegistry = .standard
    ) throws(DemoScenarioError) -> DemoScenario? {
        guard let rawMode = try value(after: wheelFlag, in: arguments) else { return nil }
        guard let mode = WheelMode(rawValue: rawMode) else { throw .unknownMode(rawMode) }
        let names = try value(after: filesFlag, in: arguments)?.split(separator: ",").map(String.init)
        let highlight = try value(after: highlightFlag, in: arguments).map { raw throws(DemoScenarioError) in
            guard let index = Int(raw), index >= 0 else { throw .badHighlight(raw) }
            return index
        }
        let payload = makePayload(names ?? sampleNames(mode), registry: registry)
        return DemoScenario(mode: mode, payload: payload, highlight: highlight)
    }

    /// The default sample selection for a mode (status-menu demo items).
    public static func sample(_ mode: WheelMode, registry: FormatRegistry = .standard) -> DemoScenario {
        DemoScenario(mode: mode, payload: makePayload(sampleNames(mode), registry: registry), highlight: nil)
    }

    static func sampleNames(_ mode: WheelMode) -> [String] {
        switch mode {
        case .convert: ["Sunset.heic"]
        case .tools: ["Interview.mov"]
        case .actions: ["Report.pdf", "Photos/"]
        }
    }

    private static func value(after flag: String, in arguments: [String]) throws(DemoScenarioError) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard arguments.indices.contains(index + 1) else { throw .missingValue(flag) }
        return arguments[index + 1]
    }

    private static func makePayload(_ names: [String], registry: FormatRegistry) -> DragPayload {
        let folder = URL(fileURLWithPath: "/tmp/ZivletDemo", isDirectory: true)
        let entries = names.map { raw in
            let isFolder = raw.hasSuffix("/")
            let name = isFolder ? String(raw.dropLast()) : raw
            let format = isFolder ? nil : registry.formatID(fileName: name)
            let kind: SelectionItemKind = isFolder ? .folder : .file
            return (
                url: folder.appending(path: name, directoryHint: isFolder ? .isDirectory : .notDirectory),
                item: SelectionItem(format, kind: kind),
                hub: HubItem(name: name, format: format, kind: kind, byteCount: isFolder ? nil : sampleBytes)
            )
        }
        return DragPayload(
            changeCount: -1, urls: entries.map(\.url), items: entries.map(\.item), hubItems: entries.map(\.hub))
    }
}
```

### 8.4 Verify green

`swift test --filter ZivletWheelTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 29 tests in 4 suites passed`.

### 8.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheel Packages/ZivletKit/Tests/ZivletWheelTests
git commit -s -m "feat(wheel): read drag payloads per change count and parse demo arguments"
```
