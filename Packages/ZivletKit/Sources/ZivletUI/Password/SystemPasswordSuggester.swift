import Foundation
import Security

/// Suggest through `SecCreateSharedWebCredentialPassword()` (17b §3.2): a new random password in the system's
/// `xxx-xxx-xxx-xxx` shape. It only generates; it reads and writes no Keychain item. The one file allowed to call it
/// (`Scripts/check-secrets.sh`); automation never does, the owner tries the button (OS-M7-4).
public final class SystemPasswordSuggester: PasswordSuggesting {
    public init() {}

    public func suggest() -> String? {
        guard let made = SecCreateSharedWebCredentialPassword() else { return nil }
        let text = made as String
        return text.isEmpty ? nil : text
    }
}
