import XCTest

/// Owner-run (D-M4-14): XCUITest drives the app through Accessibility, which needs an automation grant an
/// unattended runner cannot give. Run with `xcodebuild test -project Zivlet.xcodeproj -scheme Zivlet`.
@MainActor
final class ResultCardUITests: XCTestCase {
    func testTheFixtureCardOffersUndoRevealOpenAndCopy() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixture", dir.path]
        app.launch()
        XCTAssertTrue(app.staticTexts["Saved practice.png"].waitForExistence(timeout: 10))
        for title in ["Undo", "Reveal", "Open", "Copy"] {
            XCTAssertTrue(app.buttons[title].exists, "missing \(title)")
        }
        app.terminate()
    }
}
