import Security

/// The owner password of a restricted Lock (D-M7-20): 24 characters from the system's random source, over an alphabet
/// without the look-alikes 0, O, 1, l and I, so a person can copy it by hand. The sheet shows it once with Copy before
/// Apply; it is never stored, logged or put in settings, and becomes a `JobSecret` when the job is submitted.
nonisolated public enum OwnerPassword {
    public static let length = 24
    /// Letters and digits a person reads back without doubt.
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")

    public enum Failure: Error, Equatable {
        /// The system gave no random bytes.
        case noRandomBytes
    }

    /// `count` random bytes, or nil when the source fails.
    public typealias RandomSource = (Int) -> [UInt8]?

    /// A new password. Bytes past the largest multiple of the alphabet's size are skipped, so every character is
    /// equally likely.
    public static func make(random: RandomSource = systemRandom) throws(Failure) -> String {
        let limit = 256 - 256 % alphabet.count
        var characters: [Character] = []
        while characters.count < length {
            guard let bytes = random(length), !bytes.isEmpty else { throw .noRandomBytes }
            for byte in bytes where Int(byte) < limit && characters.count < length {
                characters.append(alphabet[Int(byte) % alphabet.count])
            }
        }
        return String(characters)
    }

    /// `SecRandomCopyBytes` over the default generator.
    public static func systemRandom(_ count: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return status == errSecSuccess ? bytes : nil
    }
}
