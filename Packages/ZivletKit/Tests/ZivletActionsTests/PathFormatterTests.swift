import Foundation
import Testing

@testable import ZivletActions

@Suite("Copy Path formatting (P1-44, 03b §7 row 5)")
struct PathFormatterTests {
    @Test func linesAreNewlineJoined() {
        let urls = ["/a/b.txt", "/c d/e.png"].map { URL(fileURLWithPath: $0) }
        #expect(PathFormatter.lines(urls) == "/a/b.txt\n/c d/e.png")
    }

    @Test(arguments: [
        ("/plain/file", "'/plain/file'"),
        ("/with space/x", "'/with space/x'"),
        ("/it's/here", #"'/it'\''s/here'"#),
        ("/$HOME/`x`/!", "'/$HOME/`x`/!'"),
        ("/new\nline", "'/new\nline'"),
    ])
    func shellQuotingSurvivesEveryMetacharacter(path: String, quoted: String) {
        #expect(PathFormatter.shell([URL(fileURLWithPath: path)]) == quoted)
    }

    @Test func shellVariantIsSpaceJoined() {
        #expect(PathFormatter.shell([URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b c")]) == "'/a' '/b c'")
    }

    @Test func quotedPathsRoundTripThroughTheShell() throws {
        let tricky = ["/tmp/it's", "/tmp/a b", "/tmp/$x", "/tmp/new\nline", "/tmp/*"].map { URL(fileURLWithPath: $0) }
        let script = "for p in \(PathFormatter.shell(tricky)); do printf '%s\\0' \"$p\"; done"
        let echoed = try Shell.run("/bin/sh", ["-c", script])
        #expect(echoed.split(separator: "\0").map(String.init) == tricky.map(\.path))
    }
}
