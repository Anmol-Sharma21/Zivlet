import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletSettings

/// P2-102 (plan 20c B7): settings and remembered tool options never hold a password. A `JobSecret` cannot be encoded
/// (B1), so this checks the stored suite itself, after the probe has caught a planted value.
@Suite("Settings and tool options hold no password")
@MainActor
struct PasswordSettingsPolicyTests {
    private let password = "zv-test-" + UUID().uuidString

    @Test func toolOptionsSavedBesideALiveSecretHoldNoPassword() throws {
        let defaults = try freshDefaults()
        let secret = JobSecret(utf8: password)
        ToolOptionsStore(defaults: defaults).save(SpeedOptions(factor: 1.5, keepsPitch: false), for: .videoSpeed)
        #expect(!secret.isWiped)
        #expect(!LeakProbe.contains(Array(password.utf8), in: try LeakProbe.bytes(of: defaults)))
        defaults.set(password, forKey: "planted")
        #expect(LeakProbe.contains(Array(password.utf8), in: try LeakProbe.bytes(of: defaults)))
    }
}
