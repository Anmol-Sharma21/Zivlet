import Foundation
import Testing

@testable import ZivletBox

/// Zip is deferred (D-M5b-11, G-M5b-1): EngineArchive (P2-111) is not built, so the box offers no Zip at all, neither
/// enabled nor greyed. When P2-111 lands, Zip joins through the `ZivletUI` coordinator (Actions must not import
/// engines), and this test changes with it.
@Suite("No Zip until EngineArchive exists (D-M5b-11)")
@MainActor
struct BoxCommandListTests {
    static let archiveWords = ["zip", "compress", "archive"]

    static func mentionsArchive(_ text: String) -> Bool {
        archiveWords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    @Test func theBarAndTheOverflowMenuHoldExactlyTheseCommands() {
        #expect(BoxPress.bar == [.share, .airDrop, .copy, .moveTo, .trash])
        #expect(BoxPress.overflow == [.copyTo, .copyPaths, .remove, .clear])
    }

    @Test func noButtonOrMenuItemOffersZip() {
        let titles = BoxPress.buttons.map(BoxCopy.title) + [BoxCopy.storage(0), BoxCopy.title(.emptyStorage)]
        #expect(!titles.contains(where: Self.mentionsArchive))
    }

    @Test func noKeyAsksForZip() {
        let keys = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)
        let strokes = keys.flatMap { key in
            [false, true].flatMap { shift in
                [false, true].map { option in BoxKeyStroke(chars: key, command: true, shift: shift, option: option) }
            }
        }
        let commands = strokes.compactMap(BoxKeyMap.command(for:)).map { String(describing: $0) }
        #expect(!commands.isEmpty && !commands.contains(where: Self.mentionsArchive))
    }

    @Test func noArchiveSymbolIsInTheBox() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/ZivletBox/BoxSymbols.swift")
        let symbols = try String(contentsOf: file, encoding: .utf8)
        #expect(!symbols.contains("zipper") && !symbols.contains("archivebox"))
    }
}
