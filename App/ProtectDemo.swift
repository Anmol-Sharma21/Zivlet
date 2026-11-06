#if DEBUG
    import AppKit
    import ZivletCore
    import ZivletUI
    import os

    /// DEBUG `-ZivletProtectDemo <folder> [-ZivletProtectDemoPause <ms>]` (plan 20f E9, exit row V8): LOCK · UNLOCK
    /// through the app's flow (the worker's pre-flight, the service, the cards) on `Report.pdf`, which the script made in
    /// `<folder>`, with a scripted prompter answering for the sheet. The password is the first line of `<folder>/secret`,
    /// a 0600 file the script wrote, deleted here once read; it is never in argv or the environment. Steps: lock,
    /// unlock the locked copy, then a wrong password and Cancel on the second sheet. Each step writes `<step>.json` (the
    /// sheets asked for and the files done or not opened, by name), `done` marks the end; `pause` leaves each card on
    /// screen for the screenshots.
    struct ProtectDemo {
        static let flag = "-ZivletProtectDemo"
        static let pauseFlag = "-ZivletProtectDemoPause"
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        let folder: URL
        let pause: Duration

        static func parse(arguments: [String]) -> ProtectDemo? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let path = arguments[index + 1]
            var isFolder: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder),
                isFolder.boolValue
            else { return nil }
            let pause = arguments.firstIndex(of: pauseFlag).flatMap {
                arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil
            }
            return ProtectDemo(folder: URL(fileURLWithPath: path, isDirectory: true), pause: .milliseconds(pause ?? 0))
        }

        @MainActor func run(protect: ProtectWiring) async {
            guard let password = readSecret() else {
                Self.logger.error("Protect demo: no secret file")
                return finish()
            }
            let report = folder.appending(path: "Report.pdf")
            let locked = folder.appending(path: "Report Locked.pdf")
            let lock = PasswordAnswer.secrets(JobSecrets(newUser: JobSecret(utf8: password)), sameForAll: true)
            await step("lock", [report], answers: [lock], protect: protect)
            let unlock = PasswordAnswer.secrets(JobSecrets(input: JobSecret(utf8: password)), sameForAll: true)
            await step("unlock", [locked], answers: [unlock], protect: protect)
            let wrong = PasswordAnswer.secrets(
                JobSecrets(input: JobSecret(utf8: "zv-wrong-\(UUID())")), sameForAll: true)
            await step("wrong", [locked], answers: [wrong, .cancelled], protect: protect)
            finish()
        }

        /// The first line of the 0600 secret file, which is removed whether or not it could be read.
        private func readSecret() -> String? {
            let file = folder.appending(path: "secret")
            defer { try? FileManager.default.removeItem(at: file) }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                (attributes[.posixPermissions] as? Int) == 0o600,
                let text = try? String(contentsOf: file, encoding: .utf8)
            else { return nil }
            return text.split(separator: "\n").first.map(String.init)
        }

        @MainActor private func step(_ name: String, _ files: [URL], answers: [PasswordAnswer], protect: ProtectWiring)
            async
        {
            let prompter = ScriptedPrompter(answers)
            let outcome = await protect.flow(near: nil, prompter: prompter).run(files, near: nil)
            let report: [String: Any] = [
                "asked": prompter.modes, "succeeded": outcome.succeeded.map(\.lastPathComponent),
                "notOpened": outcome.notOpened.map(\.lastPathComponent),
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                try data.write(to: folder.appending(path: "\(name).json"))
                Self.logger.notice("Protect demo step \(name, privacy: .public) written")
            } catch {
                Self.logger.error("Protect demo step \(name, privacy: .public) not written")
            }
            try? await Task.sleep(for: pause)
        }

        private func finish() {
            FileManager.default.createFile(atPath: folder.appending(path: "done").path, contents: Data())
        }
    }

    /// Answers each sheet in order, as a person would, and records which sheets were asked for.
    @MainActor
    private final class ScriptedPrompter: PasswordPrompting {
        private var answers: [PasswordAnswer]
        private(set) var modes: [String] = []

        init(_ answers: [PasswordAnswer]) { self.answers = answers }

        func ask(_ request: PasswordRequest) async -> PasswordAnswer {
            modes.append("\(request.mode)")
            return answers.isEmpty ? .cancelled : answers.removeFirst()
        }

        func retry(_ request: PasswordRequest, failed: [String]) async -> PasswordAnswer {
            modes.append("retry")
            return answers.isEmpty ? .cancelled : answers.removeFirst()
        }
    }
#endif
