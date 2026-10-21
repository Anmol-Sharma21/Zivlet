import Testing

@testable import ZivletUI

@Suite("Updater configuration (F2, D-M4-11)")
struct UpdaterConfigurationTests {
    static let key = String(repeating: "A", count: 43) + "="

    @Test func placeholderFeedDisablesUpdates() {
        let config = UpdaterConfiguration.validate(
            feedURL: "https://updates.zivlet.invalid/stable/appcast.xml", publicKey: Self.key)
        #expect(config == .disabled(.placeholderFeed))
    }

    @Test func missingKeyDisablesUpdates() {
        #expect(
            UpdaterConfiguration.validate(feedURL: "https://example.org/appcast.xml", publicKey: "")
                == .disabled(.missingKey))
    }

    @Test func plainHTTPIsRefused() {
        #expect(
            UpdaterConfiguration.validate(feedURL: "http://example.org/appcast.xml", publicKey: Self.key)
                == .disabled(.insecureFeed))
    }

    @Test func aRealFeedAndKeyEnableUpdates() {
        #expect(
            UpdaterConfiguration.validate(feedURL: "https://example.org/appcast.xml", publicKey: Self.key)
                == .enabled)
    }

    @Test(arguments: ["short", String(repeating: "A", count: 44) + "!", String(repeating: "#", count: 44)])
    func malformedKeysAreRefused(key: String) {
        #expect(
            UpdaterConfiguration.validate(feedURL: "https://example.org/a.xml", publicKey: key)
                == .disabled(.malformedKey))
    }

    /// An xcconfig line cuts `https://…` at `//` unless it is escaped; the truncated value must not look valid.
    @Test(arguments: ["", "https:", "https://", "not a url", "$(ZIVLET_FEED_URL)"])
    func missingOrBrokenFeedsAreRefused(feed: String) {
        #expect(UpdaterConfiguration.validate(feedURL: feed, publicKey: Self.key) == .disabled(.invalidFeed))
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(
            UpdaterConfiguration.validate(feedURL: " https://example.org/a.xml\n", publicKey: " \(Self.key) ")
                == .enabled)
    }

    @Test func aPlaceholderHostAnywhereInTheNameIsCaught() {
        #expect(
            UpdaterConfiguration.validate(feedURL: "https://feed.example.INVALID/a.xml", publicKey: Self.key)
                == .disabled(.placeholderFeed))
    }

    @Test func theInfoDictionaryKeysAreRead() {
        let info: [String: Any] = ["SUFeedURL": "https://example.org/a.xml", "SUPublicEDKey": Self.key]
        #expect(UpdaterConfiguration.from(infoDictionary: info) == .enabled)
        #expect(UpdaterConfiguration.from(infoDictionary: [:]) == .disabled(.invalidFeed))
    }

    @Test func onlyAnEnabledConfigurationStartsTheUpdater() {
        #expect(UpdaterConfiguration.enabled.startsUpdater)
        #expect(!UpdaterConfiguration.disabled(.missingKey).startsUpdater)
    }
}
