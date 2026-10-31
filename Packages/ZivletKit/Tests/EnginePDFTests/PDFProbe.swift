import Foundation

/// `zivlet-pdf-probe`, the qpdf calls in a process of their own, for tests that read what a whole process does: what it
/// prints, and how it ends.
struct PDFProbe {
    private final class BundleToken {}

    let status: Int32
    let reason: Process.TerminationReason
    let output: Data
    let errors: Data

    static var url: URL {
        Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent().appending(path: "zivlet-pdf-probe")
    }

    /// Runs the probe on `input` with three passwords on standard input (never in its arguments). A `memoryCeiling`
    /// runs its check as the worker runs one.
    static func run(
        _ input: URL, into folder: URL, passwords: [String], memoryCeiling: Int64? = nil
    ) throws -> PDFProbe {
        let process = Process()
        process.executableURL = url
        process.arguments = [input.path, folder.path] + (memoryCeiling.map { [String($0)] } ?? [])
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(passwords.map { $0 + "\n" }.joined().utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return PDFProbe(
            status: process.terminationStatus, reason: process.terminationReason, output: output, errors: errors)
    }
}
