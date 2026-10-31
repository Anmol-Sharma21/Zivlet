import EnginePDF
import Foundation
import ZivletCore
import ZivletEngineKit

// Runs the qpdf smoke calls in a process of their own, so a test can read its standard output and error and expect
// both empty (plan 20d C4). A dev tool: not shipped, not gated. It never prints; the exit status names the step that
// failed. Usage: zivlet-pdf-probe <input.pdf> <empty folder>, with three lines on standard input (never in the
// arguments): the input's password (empty for none), then the new user and owner passwords of the locked output.

enum Step: Int32 {
    case usage = 64, readPasswords = 1, inspect, check, preserve, decrypt, encrypt, reopen, refuseWrong
}

func fail(_ step: Step) -> Never { exit(step.rawValue) }

func secret(_ line: String) -> JobSecret? { line.isEmpty ? nil : JobSecret(utf8: line) }

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let inputPath = arguments.first, let folderPath = arguments.last else { fail(.usage) }
guard let password = readLine(), let newUser = readLine(), let newOwner = readLine() else { fail(.readPasswords) }

let input = URL(filePath: inputPath)
let folder = URL(filePath: folderPath, directoryHint: .isDirectory)
let opening = secret(password)
let user = JobSecret(utf8: newUser)
let owner = JobSecret(utf8: newOwner)

do { _ = try PDFInspector.inspect(input, password: opening) } catch { fail(.inspect) }
do { try QPDFDocumentReader.check(input, password: opening) } catch { fail(.check) }
do {
    try QPDFWriterBridge.write(
        input, password: opening, mode: .preserve, to: folder.appending(path: "preserved.pdf"))
} catch { fail(.preserve) }
do {
    try QPDFWriterBridge.write(input, password: opening, mode: .decrypt, to: folder.appending(path: "open.pdf"))
} catch { fail(.decrypt) }
let locked = folder.appending(path: "locked.pdf")
do {
    let parameters = R6Parameters(user: user, owner: owner)
    try QPDFWriterBridge.write(input, password: opening, mode: .encryptR6(parameters), to: locked)
} catch { fail(.encrypt) }
do {
    guard try PDFInspector.inspect(locked, password: user).matched == .user else { fail(.reopen) }
} catch { fail(.reopen) }
do {
    _ = try PDFInspector.inspect(locked, password: JobSecret(utf8: newUser + " but wrong"))
    fail(.refuseWrong)
} catch { guard error == .wrongPassword else { fail(.refuseWrong) } }
[opening, user, owner].compactMap { $0 }.forEach { $0.wipe() }
exit(0)
