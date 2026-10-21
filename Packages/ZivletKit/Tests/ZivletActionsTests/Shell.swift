import Foundation

enum ShellError: Error, Equatable {
    case failed(status: Int32)
}

/// Runs a tool with arguments (no shell parsing of our own) and returns its standard output as UTF-8.
enum Shell {
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ShellError.failed(status: process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }
}
