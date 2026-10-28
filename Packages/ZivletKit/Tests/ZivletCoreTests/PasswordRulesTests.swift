import Foundation
import Testing
import ZivletCore

/// The checks a password needs before any job (plan 20c B2, D-M7-28): strength, R6's byte limit, ASCII for the
/// non-English-letters note, and the Unicode forms of the silent retry.
@Suite("Password rules: strength, length, ASCII and Unicode forms")
struct PasswordRulesTests {
    @Test(arguments: [
        ("", PasswordRules.Strength.weak),
        ("abc", .weak),
        ("abcdefg1", .fair),
        ("abcdefgh", .weak),
        ("correct horse", .fair),
        ("Gx7!pLq2#vR9", .strong),
        ("abcdefghijklmnop", .strong),
        ("abcdefghijk1", .fair),
        ("Abcdefghij1", .fair),
        ("Abcdefghijk1", .strong),
    ])
    func strengthFollowsLengthAndCharacterClasses(_ text: String, _ expected: PasswordRules.Strength) {
        #expect(PasswordRules.strength(text) == expected)
    }

    @Test func strengthCountsCharactersNotBytes() {
        // 8 Devanagari letters are 24 bytes but 8 characters and one class (letters without case are "other").
        #expect(PasswordRules.strength("पासवर्डपासव") != .strong)
        #expect(PasswordRules.strength(String(repeating: "प", count: 16)) == .strong)
    }

    @Test func aPDFPasswordMayHave127BytesAndNoMore() {
        let fits = String(repeating: "प", count: 42) + "a"
        let tooLong = String(repeating: "प", count: 42) + "ab"
        #expect(fits.utf8.count == 127)
        #expect(PasswordRules.fitsPDF(fits))
        #expect(!PasswordRules.fitsPDF(tooLong))
        #expect(PasswordRules.pdfByteLimit == 127)
    }

    @Test func asciiIsDetected() {
        #expect(PasswordRules.isASCII("open sesame"))
        #expect(!PasswordRules.isASCII("पासवर्ड-2026"))
        #expect(!PasswordRules.isASCII("café"))
        #expect(PasswordRules.isASCII(""))
    }

    @Test func variantsAreTheTypedFormThenNFCThenNFDWithoutDuplicates() {
        let nfc = "caf\u{E9}"
        let nfd = "cafe\u{301}"
        #expect(PasswordRules.variants(nfc).map(Self.scalars) == [nfc, nfd].map(Self.scalars))
        #expect(PasswordRules.variants(nfd).map(Self.scalars) == [nfd, nfc].map(Self.scalars))
        #expect(PasswordRules.variants("open sesame") == ["open sesame"])
    }

    @Test func aMixedFormGivesThreeVariants() {
        let mixed = "caf\u{E9}-cafe\u{301}"
        let forms = PasswordRules.variants(mixed).map(Self.scalars)
        #expect(forms.count == 3)
        #expect(forms[0] == Self.scalars(mixed))
        #expect(Set(forms).count == 3)
    }

    @Test func confirmMatchesOnlyTheSamePassword() {
        #expect(PasswordRules.matches("open sesame", "open sesame"))
        #expect(!PasswordRules.matches("open sesame", "open sesame "))
        #expect(PasswordRules.matches("caf\u{E9}", "cafe\u{301}"))
    }

    private static func scalars(_ text: String) -> [UInt32] { text.unicodeScalars.map(\.value) }
}
