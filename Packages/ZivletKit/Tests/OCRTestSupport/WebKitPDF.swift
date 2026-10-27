import Foundation
import WebKit

extension PDFFixtures {
    /// A PDF made by WebKit from the Hindi sentence, a stand-in for a browser's "Save as PDF" (Chrome files come from
    /// the owner, OS-M6-3). The HTML is built here; nothing is loaded from the network.
    @MainActor
    public static func renderWebKit(into folder: URL, name: String = "webkit.pdf") async throws -> URL {
        let entry = try entry(Kind.hindi.fixture)
        let lines = entry.lines.map { "<p>\($0)</p>" }.joined()
        let html = "<html><body style='font: 24px KohinoorDevanagari-Regular; margin: 48px'>\(lines)</body></html>"
        let view = WKWebView(frame: page)
        view.loadHTMLString(html, baseURL: nil)
        for _ in 0..<100 where view.isLoading { try await Task.sleep(for: .milliseconds(50)) }
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try await view.pdf().write(to: url)
        return url
    }
}
