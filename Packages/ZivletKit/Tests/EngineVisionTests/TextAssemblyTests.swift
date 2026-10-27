import EngineVision
import Testing

@Suite("Text assembly (P2-104): one text, name separators for several files, LF and one final newline")
struct TextAssemblyTests {
    func file(_ name: String, _ pages: String...) -> FileText {
        FileText(name: name, pages: pages.map(RecognizedPage.init(text:)))
    }

    @Test func oneFileJoinsItsPagesWithABlankLine() {
        let text = TextAssembly.combine([file("report.pdf", "Page one", "Page two")])
        #expect(text.text == "Page one\n\nPage two\n")
        #expect(text.characterCount == 16)
    }

    @Test func severalFilesAreHeadedByTheirNames() {
        let text = TextAssembly.combine([file("a.png", "Alpha"), file("b.png", "बीटा"), file("c.pdf", "Gamma", "Delta")])
        #expect(text.text == "— a.png —\nAlpha\n\n— b.png —\nबीटा\n\n— c.pdf —\nGamma\n\nDelta\n")
        #expect(text.characterCount == 5 + 2 + 10)  // बीटा is two grapheme clusters
        #expect(text.scripts == [.latin, .devanagari])
        #expect(text.perFile.map(\.text) == ["Alpha\n", "बीटा\n", "Gamma\n\nDelta\n"])
    }

    @Test func aFileWithNoTextIsOmittedFromTheCombinedText() {
        let text = TextAssembly.combine([file("a.png", "Alpha"), file("blank.png", "  \n"), file("c.png", "Gamma")])
        #expect(text.text == "— a.png —\nAlpha\n\n— c.png —\nGamma\n")
        #expect(text.characterCount == 10)
        #expect(text.perFile.map(\.isEmpty) == [false, true, false])
    }

    @Test func emptyPagesInsideAFileAreSkipped() {
        #expect(TextAssembly.combine([file("a.pdf", "One", "", "Two")]).text == "One\n\nTwo\n")
    }

    @Test func nothingAtAllIsEmpty() {
        let text = TextAssembly.combine([file("a.png", ""), file("b.png", " ")])
        #expect(text.isEmpty)
        #expect(text.text == "")
        #expect(text.characterCount == 0)
        #expect(text.preview.isEmpty)
    }

    @Test func lineEndingsBecomeLFAndTrailingSpacesGo() {
        #expect(TextAssembly.combine([file("a.pdf", "one  \r\ntwo\t\rthree")]).text == "one\ntwo\nthree\n")
    }

    @Test func thePreviewIsTheFirstThreeNonEmptyLinesCut() {
        let long = String(repeating: "x", count: 100)
        let text = TextAssembly.combine([file("a.png", "\nfirst\n\nsecond\n\(long)\nfourth")])
        #expect(text.preview == ["first", "second", String(repeating: "x", count: 79) + "…"])
    }

    @Test func thePreviewOfSeveralFilesSkipsTheNameLines() {
        let text = TextAssembly.combine([file("a.png", "Alpha"), file("b.png", "Beta")])
        #expect(text.preview == ["Alpha", "Beta"])
    }
}

@Suite("Script summary (plan 18d D6): Devanagari is called Hindi, Latin is called English")
struct ScriptSummaryTests {
    static let rows: [(scripts: Set<Script>, line: String)] = [
        ([.devanagari, .latin], "Hindi and English"),
        ([.latin], "English"),
        ([.devanagari], "Hindi"),
        ([.devanagari, .latin, .other], "Hindi, English and other scripts"),
        ([.latin, .other], "English and other scripts"),
        ([.devanagari, .other], "Hindi and other scripts"),
        ([.other], "Other scripts"),
        ([], ""),
    ]

    @Test func eachSetHasItsLine() {
        for row in Self.rows {
            #expect(ScriptSummary.line(row.scripts) == row.line, "\(row.scripts)")
        }
    }
}
