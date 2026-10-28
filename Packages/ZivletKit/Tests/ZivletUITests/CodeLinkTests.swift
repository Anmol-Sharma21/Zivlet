import Foundation
import Testing

@testable import ZivletUI

@Suite("Read QR's Open is for web links only (P2-51, plan 20b A9)")
struct CodeLinkTests {
    @Test(arguments: ["https://a.b/c", "http://x", "HTTPS://X.Y", "https://zivlet.app/test?q=1#top"])
    func webLinksWithAHostCanBeOpened(payload: String) throws {
        let url = try #require(CodeLink.webURL(payload))
        #expect(url.absoluteString == payload)
    }

    @Test(arguments: [
        "javascript:alert(1)", "file:///etc/hosts", "mailto:someone@example.com", "ftp://files.example.com",
        "https://", "http:///path", "Table 12", "ZIVLET-0042", "", " https://a.b", "https://a.b/c d",
        "tel:+15550100", "data:text/html,<b>x</b>",
    ])
    func everythingElseIsNotOpened(payload: String) {
        #expect(CodeLink.webURL(payload) == nil)
    }

    @Test func linksOfOtherKindsAreNamedAsNotWebLinks() {
        #expect(CodeLink.isOtherLink("javascript:alert(1)"))
        #expect(CodeLink.isOtherLink("file:///etc/hosts"))
        #expect(!CodeLink.isOtherLink("https://a.b/c"))
        #expect(!CodeLink.isOtherLink("Table 12"))
    }
}
