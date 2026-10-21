import AppKit
import Testing
import ZivletCore
import ZivletTrigger
import ZivletWheelCore

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
