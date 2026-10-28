import Foundation

/// Checks on a typed password that need no UI (plan 20c B2). All local: nothing is sent anywhere (D-M7-28).
public enum PasswordRules {
    /// The strength hint's three steps.
    public enum Strength: Sendable, Equatable, CaseIterable {
        case weak, fair, strong
    }

    /// R6's limit: PDF 2.0 uses at most 127 bytes of a password's UTF-8, so a longer one is refused, not cut.
    public static let pdfByteLimit = 127

    private static let strongLength = 12
    private static let strongClasses = 3
    private static let anyClassStrongLength = 16
    private static let fairLength = 8

    /// Weak below 8 characters or with one class of characters; strong from 12 characters with three classes, or from
    /// 16 characters of any kind; fair otherwise. Classes: lower case, upper case, digits, everything else.
    public static func strength(_ text: String) -> Strength {
        let length = text.count
        let classes = characterClasses(text)
        if length >= anyClassStrongLength || (length >= strongLength && classes >= strongClasses) { return .strong }
        if length < fairLength || classes <= 1 { return .weak }
        return .fair
    }

    /// The password fits R6's 127-byte limit.
    public static func fitsPDF(_ text: String) -> Bool {
        text.utf8.count <= pdfByteLimit
    }

    /// Only ASCII: Preview can open the PDF (OWN-PDF-1's note is shown otherwise).
    public static func isASCII(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 0x80 }
    }

    /// The forms an unlock tries, silently, in order: as typed, then NFC, then NFD, each once. Compared by Unicode
    /// scalars, since `String`'s own equality treats canonically equal forms as one.
    public static func variants(_ text: String) -> [String] {
        let forms = [text, text.precomposedStringWithCanonicalMapping, text.decomposedStringWithCanonicalMapping]
        return forms.reduce(into: [String]()) { kept, form in
            if !kept.contains(where: { $0.unicodeScalars.elementsEqual(form.unicodeScalars) }) { kept.append(form) }
        }
    }

    /// Password and Confirm say the same (canonically equal text matches: the unlock retries both forms).
    public static func matches(_ password: String, _ confirm: String) -> Bool {
        password == confirm
    }

    private static func characterClasses(_ text: String) -> Int {
        let kinds: [(Character) -> Bool] = [\.isLowercase, \.isUppercase, \.isNumber]
        let found = kinds.filter { text.contains(where: $0) }.count
        let other = text.contains { !$0.isLowercase && !$0.isUppercase && !$0.isNumber }
        return found + (other ? 1 : 0)
    }
}
