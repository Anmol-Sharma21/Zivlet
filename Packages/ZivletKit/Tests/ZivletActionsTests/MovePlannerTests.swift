import Foundation
import Testing

@testable import ZivletActions

enum Fx {
    static func file(_ path: String) -> MoveItem { MoveItem(url: URL(fileURLWithPath: path), kind: .file) }
    static func folder(_ path: String) -> MoveItem { MoveItem(url: URL(fileURLWithPath: path), kind: .folder) }
    static func package(_ path: String) -> MoveItem { MoveItem(url: URL(fileURLWithPath: path), kind: .package) }
    static func url(_ path: String) -> URL { URL(fileURLWithPath: path) }
}

@Suite("Move planner (P1-45)")
struct MovePlannerTests {
    let vol = VolumeID(1)

    @Test func collisionsGetTheNextFreeName() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.file("/src/a.txt")], destination: Fx.folder("/dst"),
            volumes: { _ in vol }, existing: ["/dst/a.txt", "/dst/a 2.txt"])
        #expect(plan.steps.map(\.target.path) == ["/dst/a 3.txt"])
        #expect(plan.steps.map(\.kind) == [.rename])
        #expect(plan.steps.map(\.source) == [Fx.url("/src/a.txt")])
    }

    @Test func collisionsIgnoreCaseAndUnicodeForm() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.file("/src/Caf\u{E9}.TXT")], destination: Fx.folder("/dst"),
            volumes: { _ in vol }, existing: ["/dst/cafe\u{301}.txt"])
        #expect(plan.steps.map(\.target.lastPathComponent) == ["Caf\u{E9} 2.TXT"])
    }

    @Test func foldersPackagesAndCompoundExtensionsStepLikeFinder() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.folder("/s/My.Folder"), Fx.package("/s/Tool.app"), Fx.file("/s/b.tar.gz"), Fx.file("/s/.env")],
            destination: Fx.folder("/d"), volumes: { _ in vol },
            existing: ["/d/My.Folder", "/d/Tool.app", "/d/b.tar.gz", "/d/.env"])
        #expect(plan.steps.map(\.target.lastPathComponent) == ["My.Folder 2", "Tool 2.app", "b 2.tar.gz", ".env 2"])
    }

    @Test func aFolderCannotMoveIntoItselfOrItsChild() {
        #expect(throws: MoveRefusal.intoItself(Fx.url("/src/f"))) {
            try MovePlanner.plan(
                items: [Fx.folder("/src/f")], destination: Fx.folder("/src/f/inner"), volumes: { _ in vol },
                existing: [])
        }
        #expect(throws: MoveRefusal.intoItself(Fx.url("/src/f"))) {
            try MovePlanner.plan(
                items: [Fx.folder("/src/f")], destination: Fx.folder("/src/f"), volumes: { _ in vol }, existing: [])
        }
    }

    @Test func aSiblingWithTheSamePrefixIsNotInsideTheFolder() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.folder("/src/f")], destination: Fx.folder("/src/f2"), volumes: { _ in vol }, existing: [])
        #expect(plan.steps.map(\.target.path) == ["/src/f2/f"])
    }

    @Test func theDestinationMustBeAFolder() {
        #expect(throws: MoveRefusal.notAFolder) {
            try MovePlanner.plan(
                items: [Fx.file("/a.txt")], destination: Fx.file("/b.txt"), volumes: { _ in vol }, existing: [])
        }
        #expect(throws: MoveRefusal.notAFolder) {
            try MovePlanner.plan(
                items: [Fx.file("/a.txt")], destination: Fx.package("/X.app"), volumes: { _ in vol }, existing: [])
        }
    }

    @Test func itemsAlreadyThereAreSkipped() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.file("/dst/a.txt")], destination: Fx.folder("/dst"), volumes: { _ in vol },
            existing: ["/dst/a.txt"])
        #expect(plan.steps.isEmpty && plan.skipped == [.alreadyThere(Fx.url("/dst/a.txt"))])
    }

    @Test func crossVolumeBecomesCopyThenTrash() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.file("/src/a.txt")], destination: Fx.folder("/Volumes/USB"),
            volumes: { $0.path.hasPrefix("/Volumes/USB") ? VolumeID(2) : VolumeID(1) }, existing: [])
        #expect(plan.steps.map(\.kind) == [.copyThenTrash])
    }

    @Test func twoItemsWithTheSameNameGetDistinctTargets() throws {
        let plan = try MovePlanner.plan(
            items: [Fx.file("/x/a.txt"), Fx.file("/y/a.txt")], destination: Fx.folder("/d"),
            volumes: { _ in vol }, existing: [])
        #expect(plan.steps.map(\.target.lastPathComponent) == ["a.txt", "a 2.txt"])
    }

    @Test func whenEveryNameIsTakenTheItemIsRefused() {
        let taken = Set(["/d/a.txt"] + (2...MoveNames.maxCandidates).map { "/d/a \($0).txt" })
        #expect(throws: MoveRefusal.noFreeName(Fx.url("/s/a.txt"))) {
            try MovePlanner.plan(
                items: [Fx.file("/s/a.txt")], destination: Fx.folder("/d"), volumes: { _ in vol }, existing: taken)
        }
    }

    @Test func longNamesStayWithinTheFileNameLimit() {
        let stem = String(repeating: "\u{E9}", count: 127)
        let name = MoveNames.candidate("\(stem).txt", counter: 2, kind: .file)
        #expect(name.utf8.count <= 255 && name.hasSuffix(" 2.txt"))
    }

    @Test func refusalsHaveUserCopy() {
        #expect(MoveRefusal.notAFolder.userMessage == "Choose a folder on this Mac to move into.")
        #expect(MoveRefusal.intoItself(Fx.url("/s/Photos")).userMessage == "“Photos” can't be moved into itself.")
        #expect(
            MoveRefusal.noFreeName(Fx.url("/s/a.txt")).userMessage
                == "Every name for “a.txt” is already taken in that folder.")
    }
}
