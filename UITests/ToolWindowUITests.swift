import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Owner-run (D-M4-14, OS-M7-10): drives the tool window through Accessibility. READ QR runs on a QR code this test
/// draws with Core Image, through `-UITestFixture <dir> -UITestMode tools -UITestTool qrScan` (D-M7-12); the window
/// shows the payload with Open and Copy All, and Escape closes it. Nothing is copied or opened.
@MainActor
final class ToolWindowUITests: XCTestCase {
    static let payload = "https://zivlet.app/test"

    func testReadQRShowsTheCodeAndEscapeClosesTheWindow() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeQR(Self.payload, to: dir.appending(path: "code.png"))
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFixture", dir.path, "-UITestMode", "tools", "-UITestTool", "qrScan"]
        app.launch()
        let copyAll = app.buttons["Copy All"]
        XCTAssertTrue(copyAll.waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts[Self.payload].exists)
        XCTAssertTrue(app.buttons["Open"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(copyAll.waitForNonExistence(timeout: 5))
        app.terminate()
    }

    static func writeQR(_ payload: String, to url: URL) throws {
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let output = try XCTUnwrap(filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)))
        let image = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
