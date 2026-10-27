import OCRTestSupport
import Testing

@Suite("Character error rate (D-M6-12): Levenshtein over scalars after NFC and whitespace collapse")
struct CharacterErrorRateTests {
    @Test func identicalTextCostsNothing() {
        #expect(CharacterErrorRate.cer(reference: "आज मौसम अच्छा है", hypothesis: "आज मौसम अच्छा है") == 0)
    }

    @Test func oneSubstitutionInTenScalarsIsATenth() {
        #expect(CharacterErrorRate.cer(reference: "abcdefghij", hypothesis: "abcdXfghij") == 0.1)
    }

    @Test func canonicalEquivalentsCostNothing() {
        #expect(CharacterErrorRate.cer(reference: "रोज़", hypothesis: "रोज\u{093C}") == 0)
        #expect(CharacterErrorRate.cer(reference: "\u{095B}", hypothesis: "\u{091C}\u{093C}") == 0)
    }

    @Test func whitespaceRunsAndNewlinesCollapse() {
        #expect(CharacterErrorRate.cer(reference: "one two\nthree", hypothesis: "  one   two \n\n three \n") == 0)
    }

    @Test func emptyReferenceScoresZeroOrOne() {
        #expect(CharacterErrorRate.cer(reference: "", hypothesis: "") == 0)
        #expect(CharacterErrorRate.cer(reference: "", hypothesis: "text") == 1)
        #expect(CharacterErrorRate.cer(reference: " \n", hypothesis: "") == 0)
    }

    @Test func insertionsPastTheEndCount() {
        #expect(CharacterErrorRate.cer(reference: "abcd", hypothesis: "abcdef") == 0.5)
    }

    @Test func deletionsCount() {
        #expect(CharacterErrorRate.cer(reference: "abcd", hypothesis: "ab") == 0.5)
    }

    @Test func devanagariIsFoundByItsBlock() {
        #expect(Devanagari.contains("Please carry your पहचान card"))
        #expect(!Devanagari.contains("Please carry your card ₹40"))
        #expect(Devanagari.contains("१५"))
    }
}
