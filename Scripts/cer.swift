// Character error rate between two UTF-8 files, the rule of plan 18d D-M6-12 (the same as OCRTestSupport's
// CharacterErrorRate): Levenshtein over Unicode scalars divided by the reference's scalar count, after NFC and
// collapsing every whitespace run to one space. Prints the rate with three decimals.
// Usage: xcrun swift Scripts/cer.swift <reference-file> <hypothesis-file>
import Foundation

func normalized(_ text: String) -> [Unicode.Scalar] {
    let collapsed = text.precomposedStringWithCanonicalMapping
        .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    return Array(collapsed.unicodeScalars)
}

func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
    guard !b.isEmpty else { return a.count }
    var previous = Array(0...b.count)
    for (i, left) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, right) in b.enumerated() {
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1))
        }
        previous = current
    }
    return previous[b.count]
}

let arguments = CommandLine.arguments
guard arguments.count == 3,
    let reference = try? String(contentsOfFile: arguments[1], encoding: .utf8),
    let hypothesis = try? String(contentsOfFile: arguments[2], encoding: .utf8)
else {
    FileHandle.standardError.write(Data("usage: cer.swift <reference-file> <hypothesis-file> (UTF-8)\n".utf8))
    exit(2)
}
let truth = normalized(reference)
let guess = normalized(hypothesis)
let rate = truth.isEmpty ? (guess.isEmpty ? 0 : 1) : Double(distance(truth, guess)) / Double(truth.count)
FileHandle.standardOutput.write(Data(String(format: "%.3f\n", rate).utf8))
