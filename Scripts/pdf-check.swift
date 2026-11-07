// Checks LOCK · UNLOCK outputs with PDFKit (plan 20g F3, exit rows V6 and V8). Everything comes on stdin, so no
// password is ever in argv or the environment: first the passwords, one per line, then an empty line, then one check
// per line with tab-separated fields (file names may hold spaces). Password numbers are 1-based; 0 is a made-up wrong
// one. Checks:
//   opens <file> <n>            locked, and password n opens it
//   refuses <file> <n>          locked, and password n does not open it
//   owner <file> <n>            password n opens it as its owner (every permission)
//   restricted <file> <n>       password n opens it as a user who may neither print nor copy
//   plain <file>                not encrypted
//   fields <file> <count> [n]   at least <count> form widgets (after opening with password n)
// Prints PASS or FAIL per check with the file's name only, never a password. Exit 1 when a check failed, 2 on bad
// input.
// Usage: printf '%s\n' "$p1" "$p2" '' 'opens	/abs/X Locked.pdf	1' | xcrun swift Scripts/pdf-check.swift
import Foundation
import PDFKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

func say(_ line: String) { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }

let lines = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
guard let gap = lines.firstIndex(of: "") else { fail("no empty line after the passwords") }
let passwords = Array(lines[..<gap])
let checks = lines[(gap + 1)...].filter { !$0.isEmpty }
guard !checks.isEmpty else { fail("no checks") }

func password(_ field: String) -> String {
    guard let number = Int(field), (0...passwords.count).contains(number) else { fail("bad password number \(field)") }
    return number == 0 ? "zv-wrong-\(UUID().uuidString)" : passwords[number - 1]
}

func document(_ path: String) -> PDFDocument? {
    guard path.hasPrefix("/") else { fail("not an absolute path: \(path)") }
    return PDFDocument(url: URL(fileURLWithPath: path))
}

func widgets(_ document: PDFDocument) -> Int {
    (0..<document.pageCount).compactMap { document.page(at: $0) }.flatMap(\.annotations)
        .filter { $0.type == "Widget" }.count
}

/// True when the check holds; nil when the line is not a check.
func run(_ fields: [String]) -> Bool? {
    guard fields.count >= 2, let doc = document(fields[1]) else { return fields.count >= 2 ? false : nil }
    switch (fields[0], fields.count) {
    case ("opens", 3): return doc.isLocked && doc.unlock(withPassword: password(fields[2]))
    case ("refuses", 3): return doc.isLocked && !doc.unlock(withPassword: password(fields[2]))
    case ("owner", 3): return doc.unlock(withPassword: password(fields[2])) && doc.permissionsStatus == .owner
    case ("restricted", 3):
        return doc.unlock(withPassword: password(fields[2])) && doc.permissionsStatus == .user && !doc.allowsCopying
            && !doc.allowsPrinting
    case ("plain", 2): return !doc.isEncrypted && !doc.isLocked
    case ("fields", 3), ("fields", 4):
        guard let count = Int(fields[2]) else { return nil }
        if fields.count == 4, !doc.unlock(withPassword: password(fields[3])) { return false }
        return !doc.isLocked && widgets(doc) >= count
    default: return nil
    }
}

var failed = false
for check in checks {
    let fields = check.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard let held = run(fields) else { fail("not a check: \(fields.first ?? "")") }
    let name = URL(fileURLWithPath: fields[1]).lastPathComponent
    say("\(held ? "PASS" : "FAIL") \(fields[0]) \(name)")
    failed = failed || !held
}
exit(failed ? 1 : 0)
