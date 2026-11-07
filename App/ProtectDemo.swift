#if DEBUG
    import AppKit
    import ZivletCore
    import ZivletUI
    import os

    /// DEBUG `-ZivletProtectDemo <folder> [-ZivletProtectDemoPause <ms>]` (plan 20f E9, 20g F3, exit rows V6 and V8):
    /// LOCK · UNLOCK through the app's flow (the worker's pre-flight, the service, the cards) on PDFs the script made
    /// in `<folder>`, with a scripted prompter answering for the sheet. `<folder>/steps.json` lists the steps (see
    /// `ProtectDemoStep`); the passwords are the lines of `<folder>/secret`, a 0600 file deleted once read
    /// (`DemoSecrets`), so none is ever in argv or the environment. Each step writes `<step>.json` (the sheets asked
    /// for, the files done or not opened, and the new files in the folder, by name) and logs the near-drop card's
    /// window (`ShotFrame`); `done` marks the end; `pause` leaves each card on screen for a look.
    struct ProtectDemo {
        static let flag = "-ZivletProtectDemo"
        static let pauseFlag = "-ZivletProtectDemoPause"
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        let folder: URL
        let pause: Duration

        static func parse(arguments: [String]) -> ProtectDemo? {
            guard let folder = DemoFolder.parse(flag, arguments: arguments) else { return nil }
            let pause = arguments.firstIndex(of: pauseFlag).flatMap {
                arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil
            }
            return ProtectDemo(folder: folder, pause: .milliseconds(min(max(pause ?? 0, 0), 10_000)))
        }

        @MainActor func run(protect: ProtectWiring) async {
            guard let passwords = DemoSecrets.read(in: folder) else {
                Self.logger.error("Protect demo: no secret file")
                return DemoFolder.finish(folder)
            }
            guard let steps = ProtectDemoStep.load(from: folder, passwords: passwords.count) else {
                Self.logger.error("Protect demo: steps refused")
                return DemoFolder.finish(folder)
            }
            for step in steps {
                await run(step, passwords: passwords, protect: protect)
            }
            DemoFolder.finish(folder)
        }

        @MainActor private func run(_ step: ProtectDemoStep, passwords: [String], protect: ProtectWiring) async {
            let before = pdfNames()
            let prompter = ScriptedPrompter(step.answers.map { $0.answer(passwords) })
            let files = step.files.map { folder.appending(path: $0) }
            let outcome = await protect.flow(near: nil, prompter: prompter).run(files, near: nil)
            let report: [String: Any] = [
                "asked": prompter.modes, "succeeded": outcome.succeeded.map(\.lastPathComponent),
                "notOpened": outcome.notOpened.map(\.lastPathComponent),
                "outputs": pdfNames().subtracting(before).sorted(),
            ]
            DemoFolder.write(report, named: step.name, in: folder, logger: Self.logger)
            try? await Task.sleep(for: .milliseconds(600))
            Self.logger.notice("Protect demo: \(step.name, privacy: .public) shown")
            if let card = ShotFrame.visible(HUDWindow.self) { ShotFrame.log("Protect demo", card, logger: Self.logger) }
            try? await Task.sleep(for: pause)
        }

        private func pdfNames() -> Set<String> {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return Set(names.filter { $0.lowercased().hasSuffix(".pdf") })
        }
    }

    /// One step of `steps.json`: a name (lower-case letters, digits and dashes), the folder's PDFs to drop by name,
    /// and the answers the sheets get in order. In an answer, `input`, `newUser` and `owner` are 1-based lines of the
    /// secret file, or 0 for a made-up wrong password; `restrict` turns printing, copying and editing off; `cancel`
    /// presses Cancel.
    struct ProtectDemoStep: Decodable {
        struct Answer: Decodable {
            let input: Int?
            let newUser: Int?
            let owner: Int?
            let restrict: Bool?
            let cancel: Bool?

            var indices: [Int] { [input, newUser, owner].compactMap { $0 } }

            func answer(_ passwords: [String]) -> PasswordAnswer {
                guard cancel != true else { return .cancelled }
                let secret = { (index: Int?) -> JobSecret? in
                    index.map { JobSecret(utf8: $0 == 0 ? "zv-wrong-\(UUID())" : passwords[$0 - 1]) }
                }
                let restrictions =
                    restrict == true ? PDFRestrictions(printing: .none, copying: false, editing: false) : nil
                let secrets = JobSecrets(input: secret(input), newUser: secret(newUser), owner: secret(owner))
                return .secrets(secrets, sameForAll: true, restrictions: restrictions)
            }
        }

        static let maxSteps = 12
        static let maxAnswers = 6

        let name: String
        let files: [String]
        let answers: [Answer]

        /// The steps, validated: plain names, at most 12 steps of at most 6 answers, indices within the secret file.
        static func load(from folder: URL, passwords: Int) -> [ProtectDemoStep]? {
            guard let data = try? Data(contentsOf: folder.appending(path: "steps.json")),
                let steps = try? JSONDecoder().decode([ProtectDemoStep].self, from: data),
                (1...maxSteps).contains(steps.count)
            else { return nil }
            return steps.allSatisfy { $0.isValid(passwords: passwords) } ? steps : nil
        }

        private func isValid(passwords: Int) -> Bool {
            let plainName = { (name: String) in
                !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && name.count <= 128
            }
            return name.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil
                && !files.isEmpty && files.count <= 20 && files.allSatisfy(plainName)
                && answers.count <= Self.maxAnswers
                && answers.allSatisfy { $0.indices.allSatisfy { (0...passwords).contains($0) } }
        }
    }
#endif
