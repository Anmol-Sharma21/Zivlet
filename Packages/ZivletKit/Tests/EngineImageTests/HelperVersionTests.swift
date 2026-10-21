import Foundation
import Testing
import ZivletEngineKit

@testable import EngineImage

@Suite("Helper versions for Settings › Advanced (D3)")
struct ImageHelperVersionTests {
    @Test func libwebpAndResvgAreReported() async {
        let versions = await ImageEngine().helperVersions()
        #expect(versions.map(\.name) == ["libwebp", "resvg"])
        #expect(versions.first?.version == "1.6.0")
    }

    /// The resvg number is a constant (the C ABI has no version call); it must follow the crate's pin.
    @Test func theResvgConstantFollowsTheCratePin() throws {
        let cargo = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../Vendor/rs/zivlet-svg/Cargo.toml")
        let manifest = try String(contentsOf: cargo, encoding: .utf8)
        #expect(manifest.contains(#"resvg = { version = "=\#(ImageEngine.resvgVersion)""#))
    }
}
