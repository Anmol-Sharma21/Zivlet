import Foundation
import ZivletCore
import ZivletRuntime

// Debug builds only: a canned finished batch for the owner-run UI test (D-M4-14).
#if DEBUG
    /// `-UITestFixture <dir>` shows the result card for one saved file in `<dir>` (Zivlet's own practice drawing), so
    /// the XCUITest target can check the card without a drag or a conversion.
    public enum UITestFixture {
        public static let flag = "-UITestFixture"
        static let sourceBytes: Int64 = 2_100_000

        /// The fixture directory, when the flag names an absolute path.
        public static func directory(arguments: [String]) -> URL? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count,
                arguments[index + 1].hasPrefix("/")
            else { return nil }
            return URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        }

        /// A finished one-file batch: photo.heic → the practice PNG written into `dir`.
        public static func snapshot(in dir: URL) throws -> BatchSnapshot {
            let output = try OnboardingSample.make(in: dir)
            let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? 0
            let input = try InputItem(url: dir.appending(path: "photo.heic"), format: .heic, byteCount: sourceBytes)
            let request = try JobRequest(input: input, operation: .convert(.png), destination: dir)
            let batch = BatchID()
            let published = PublishedOutput(url: output, format: .png, byteCount: size, fileID: 0, modified: Date())
            return BatchSnapshot(batch: batch, target: .png, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .succeeded(published))).applying(.finished(batch))
        }
    }
#endif
