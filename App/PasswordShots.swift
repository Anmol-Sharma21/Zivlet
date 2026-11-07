#if DEBUG
    import AppKit
    import ZivletCore
    import ZivletUI
    import os

    /// DEBUG `-ZivletPasswordStates <state>` (plan 20c B4, 20g): one password sheet state in the tool window at the
    /// main screen's centre, for screenshots. The typed text is made up here per launch (never a real password) and the
    /// Suggest state uses a fake generator, so the system's is never called. Logs `Password shot: <state> window <n>`
    /// and `Password shot: window <n> frame x y w h` once the window shows. Apply and Cancel only close it.
    enum PasswordShots {
        enum State: String, CaseIterable {
            case lockEmpty, lockMismatch, lockSuggested, lockNonASCII, lockRestricted, unlockWrong, unlockBatch, retry,
                change, changeRetry, ownerNeeded, open
        }

        static let flag = "-ZivletPasswordStates"
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        static func parse(arguments: [String]) -> State? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return State(rawValue: arguments[index + 1])
        }

        /// A made-up password in the system generator's shape, new each launch.
        private static func madeUp() -> String {
            let letters = Array("abcdefghjkmnpqrstuvwxyz")
            let group = { String((0..<3).map { _ in letters.randomElement() ?? "a" }) }
            return "\(group())-\(group().uppercased())-\(Int.random(in: 100...999))-\(group())"
        }

        @MainActor static func run(_ state: State, toolWindows: ToolWindowWiring) {
            let suggestion = madeUp()
            let prompter = PasswordPrompter(presenter: toolWindows.coordinator) { model in
                PasswordSheetState(model: model, suggester: FakeSuggester(suggestion))
            }
            let center = NSScreen.main.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
            let request = PasswordRequest(mode: mode(state), files: files(state), near: center)
            Task { @MainActor in
                if state == .retry || state == .changeRetry {
                    _ = await prompter.retry(request, failed: Array(files(state).prefix(2)))
                } else {
                    _ = await prompter.ask(request)
                }
            }
            Task { @MainActor in
                while prompter.showing == nil { try? await Task.sleep(for: .milliseconds(50)) }
                if let sheet = prompter.showing { fill(sheet, state: state, suggestion: suggestion) }
                try? await Task.sleep(for: .milliseconds(400))
                let window = NSApp.windows.first { $0 is ToolWindow && $0.isVisible }
                let number = window?.windowNumber ?? 0
                let size = window?.frame.size ?? .zero
                logger.notice(
                    "Password shot: \(state.rawValue, privacy: .public) window \(number, privacy: .public) size \(Int(size.width), privacy: .public)x\(Int(size.height), privacy: .public)"
                )
                if let window { ShotFrame.log("Password shot", window, logger: logger) }
            }
        }

        private static func mode(_ state: State) -> PasswordMode {
            switch state {
            case .lockEmpty, .lockMismatch, .lockSuggested, .lockNonASCII, .lockRestricted: .lock
            case .unlockWrong, .unlockBatch, .retry: .unlock
            case .change, .changeRetry: .change
            case .ownerNeeded: .ownerNeeded
            case .open: .open
            }
        }

        private static func files(_ state: State) -> [String] {
            switch state {
            case .unlockBatch, .retry: ["Budget 2026.pdf", "Lease.pdf", "Menu.pdf"]
            default: ["Budget 2026.pdf"]
            }
        }

        @MainActor private static func fill(_ sheet: PasswordSheetState, state: State, suggestion: String) {
            switch state {
            case .lockMismatch:
                sheet.password = suggestion
                sheet.confirm = String(suggestion.dropLast())
            case .lockSuggested: sheet.suggest()
            case .lockNonASCII:
                let text = "पासवर्ड-" + suggestion
                sheet.password = text
                sheet.confirm = text
                sheet.toggleReveal(.password)
                sheet.toggleReveal(.confirm)
            case .lockRestricted:
                sheet.password = suggestion
                sheet.confirm = suggestion
                sheet.setRestrictions(PDFRestrictions(printing: .low, copying: false, editing: false))
            case .unlockWrong, .open: sheet.wrongAttempt()
            case .change:
                sheet.current = String(suggestion.reversed())
                sheet.password = suggestion
                sheet.confirm = suggestion
            case .changeRetry:  // the second sheet has shaken once already
                sheet.password = suggestion
                sheet.confirm = suggestion
            case .lockEmpty, .unlockBatch, .retry, .ownerNeeded: break
            }
        }
    }
#endif
