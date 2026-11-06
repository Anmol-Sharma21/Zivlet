import Testing

@testable import ZivletUI

/// The owner password of a restricted Lock (D-M7-20): 24 characters the app makes from the system's random source,
/// from an alphabet a person can read back without mistaking one character for another; shown once, never stored.
@Suite("A random owner password for restrictions")
struct OwnerPasswordTests {
    @Test func itIs24CharactersFromTheUnambiguousAlphabet() throws {
        let password = try OwnerPassword.make()
        #expect(password.count == 24)
        #expect(password.allSatisfy { OwnerPassword.alphabet.contains($0) })
    }

    @Test func theAlphabetHasNoLookAlikes() {
        for confusable in ["0", "O", "1", "l", "I"] {
            #expect(!OwnerPassword.alphabet.contains(Character(confusable)))
        }
        #expect(Set(OwnerPassword.alphabet).count == OwnerPassword.alphabet.count)
        #expect(OwnerPassword.alphabet.allSatisfy { $0.isASCII })
    }

    @Test func twoPasswordsDiffer() throws {
        let (one, two) = (try OwnerPassword.make(), try OwnerPassword.make())
        #expect(one != two)
    }

    /// Bytes past the largest multiple of the alphabet's size are dropped, so no character is likelier than another.
    @Test func bytesOutsideTheEvenRangeAreSkipped() throws {
        let size = OwnerPassword.alphabet.count
        let limit = 256 - 256 % size
        var bytes = [UInt8(limit), UInt8(255)] + (0..<24).map { UInt8($0) }
        let password = try OwnerPassword.make { count in
            defer { bytes.removeFirst(min(count, bytes.count)) }
            return Array(bytes.prefix(count))
        }
        #expect(password == String((0..<24).map { OwnerPassword.alphabet[$0 % size] }))
    }

    @Test func aRandomSourceThatFailsIsAnError() {
        #expect(throws: OwnerPassword.Failure.noRandomBytes) { try OwnerPassword.make { _ in nil } }
    }
}
