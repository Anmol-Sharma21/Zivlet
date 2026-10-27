import Foundation

extension OCRFixtures {
    /// Real-Vision tests run only in `make ocr-check` (D-M6-13): a cold model compile takes minutes.
    public static var realVisionEnabled: Bool { ProcessInfo.processInfo.environment["ZIVLET_OCR_FIXTURES"] == "1" }

    /// One line on standard error, so `make ocr-check` shows the measurements (no `print`).
    public static func log(_ line: String) {
        FileHandle.standardError.write(Data(("ocr-check: " + line + "\n").utf8))
    }
}
