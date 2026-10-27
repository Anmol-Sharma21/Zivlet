import AppKit
import Carbon
import EngineVision
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletSettings
import ZivletUI
import os

/// Copy Text from the wheel (P2-104, plan 18d D12): the languages from the setting, the person's languages and
/// keyboards and this Mac's Vision; the working line where the placement says; the job in the worker (`TextService`);
/// the clipboard; with ⌥ one `.txt` per input; then the text card, "No text found" or the error's sentence. The card's
/// buttons copy again, save the files, or open Show All. After onboarding it warms text recognition up once per OS
/// build and language set (D-M6-16). The text itself is never logged or stored (D14).
final class ToolWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    private let text: TextService
    private let actions: ActionWiring
    private let store: SettingsStore
    private let clipboard: ClipboardAction
    /// Show All; the DEBUG text states show it too.
    let preview = TextPreviewWindow()
    private var capabilities: VisionCapabilities?
    private var warmup: WarmupState?
    private var languageWatch: Task<Void, Never>?
    /// The DEBUG Copy Text demo's choice, in memory only (the person's settings are never written by a demo).
    var choiceOverride: TextLanguageChoice?

    /// `clipboard` is the general pasteboard; the DEBUG Copy Text demo passes a private one.
    init(text: TextService, actions: ActionWiring, store: SettingsStore, clipboard: ClipboardAction = ClipboardAction())
    {
        self.text = text
        self.clipboard = clipboard
        self.actions = actions
        self.store = store
        actions.onTextButton = { [weak self] button, outcome in self?.pressed(button, outcome) }
        watchLanguageChoice()
    }

    /// Whether this Mac's Vision reads Hindi, once the worker has said; nil before (Settings offers every choice).
    var hindiAvailable: Bool? { capabilities?.hasHindi }

    /// A new language choice needs its own warm-up (D7): it starts at once.
    private func watchLanguageChoice() {
        let changes = store.changes
        var last = store.current.text.language
        languageWatch = Task { @MainActor [weak self] in
            for await settings in changes where settings.text.language != last {
                last = settings.text.language
                self?.startWarmUpIfNeeded()
            }
        }
    }

    /// Runs `tool` when it is wired; nil leaves it to the DEBUG note (the other tools wait for their windows).
    @discardableResult
    func run(_ tool: ToolID, urls: [URL], optionHeld: Bool, near point: CGPoint?) -> Task<ActionResult, Never>? {
        guard tool == .copyText else { return nil }
        let presenter = actions.currentPresenter
        return Task { @MainActor in
            let job = WorkingLine(presenter: presenter, point: point)
            let result = await self.copyText(urls, optionHeld: optionHeld, line: job)
            job.finish()
            presenter.show(result, near: point)
            self.log(result, files: urls.count)
            self.startWarmUpIfNeeded()
            return result
        }
    }

    /// After onboarding (at once), and at each launch until it is done (after `delay`, so launch stays quick); never
    /// during a DEBUG demo or UI test run.
    func startWarmUpIfNeeded(after delay: Duration = .zero, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard store.current.onboarding.completed, !Self.isDemoRun(arguments) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            await self.warmUpIfNeeded()
        }
    }

    /// A DEBUG demo or UI test run; a Release build has none (its flags are never compiled in, check-release-paths).
    private static func isDemoRun(_ arguments: [String]) -> Bool {
        #if DEBUG
            let prefixes = ["-ZivletDemo", "-ZivletCopyTextDemo", "-ZivletTextStates", "-ZivletIslandPreview"]
            return arguments.contains { argument in
                prefixes.contains { argument.hasPrefix($0) } || argument == "-UITestFixture"
            }
        #else
            return false
        #endif
    }

    private func copyText(_ urls: [URL], optionHeld: Bool, line: WorkingLine) async -> ActionResult {
        do {
            let (languages, warmed) = try await languages()
            line.show(ToolWiringModel.workingLine(warmupDone: warmed, fraction: nil))
            let recognized = try await text.copyText(urls, languages: languages) { fraction in
                Task { @MainActor in line.show(ToolWiringModel.workingLine(warmupDone: warmed, fraction: fraction)) }
            }
            return finish(recognized, sources: urls, optionHeld: optionHeld)
        } catch {
            return ToolWiringModel.failure(error)
        }
    }

    /// The clipboard first; with ⌥ the files; then the card.
    private func finish(_ recognized: RecognizedText, sources: [URL], optionHeld: Bool) -> ActionResult {
        guard !recognized.isEmpty else { return ToolWiringModel.result(recognized, sources: sources, saved: []) }
        if case .failed(let error) = clipboard.copyText(recognized.text) { return ActionResult(.failed(error)) }
        guard ToolWiringModel.writesFiles(optionHeld: optionHeld) else {
            return ToolWiringModel.result(recognized, sources: sources, saved: [])
        }
        let files = zip(sources, recognized.perFile).filter { !$0.1.isEmpty }.map {
            TextFile(source: $0.0, text: $0.1.text)
        }
        switch save(files) {
        case .saved(let saved): return ToolWiringModel.result(recognized, sources: sources, saved: saved)
        case .failed(let card): return .failed(card)
        }
    }

    private func pressed(_ button: TextResultButton, _ outcome: TextOutcome) {
        switch button {
        case .copyAgain:
            if case .failed(let error) = clipboard.copyText(outcome.fullText) {
                actions.present(ActionResult(.failed(error)), near: nil)
            }
        case .saveText:
            switch save(outcome.text.files) {
            case .saved(let saved):
                actions.present(.done(toast: ToolWiringModel.savedToast(saved), undo: nil), near: nil)
            case .failed(let card):
                actions.present(.failed(card), near: nil)
            }
        case .showAll:
            preview.show(TextPreviewModel(title: outcome.windowTitle, text: outcome.fullText))
        }
    }

    /// One `.txt` per input beside it (or in the fallback folder); the first failure stops and is named.
    private enum Saved {
        case saved([URL])
        case failed(ActionCard)
    }

    private func save(_ files: [TextFile]) -> Saved {
        let writer = TextFileWriter(fallbackFolder: URL(fileURLWithPath: store.current.output.fallbackFolder))
        var saved: [URL] = []
        for file in files {
            do {
                saved.append(try writer.write(file.text, beside: file.source))
            } catch {
                let lines = [file.source.lastPathComponent, JobErrorCopy.copy(for: error).message]
                return .failed(ActionCard(title: "A text file wasn't saved.", lines: lines))
            }
        }
        return .saved(saved)
    }

    /// The ordered languages and whether the warm-up is done for them on this OS build.
    private func languages() async throws(TextError) -> ([LanguageTag], Bool) {
        let capabilities = try await currentCapabilities()
        let languages = RecognitionLanguages.defaults(
            preferred: Locale.preferredLanguages, inputSources: Self.enabledInputSources(),
            choice: choiceOverride ?? store.current.text.language, capabilities: capabilities)
        let record = TextWarmupRecord(osBuild: capabilities.osBuild, languages: languages)
        return (languages, store.current.text.warmed == record)
    }

    private func currentCapabilities() async throws(TextError) -> VisionCapabilities {
        if let capabilities { return capabilities }
        let fetched = try await text.capabilities()
        capabilities = fetched
        return fetched
    }

    /// Runs the warm-up when the state says so; a failure stays needed until the next launch (no loop).
    private func warmUpIfNeeded() async {
        guard store.current.onboarding.completed, let capabilities = try? await currentCapabilities(),
            let (languages, _) = try? await languages()
        else { return }
        let record = TextWarmupRecord(osBuild: capabilities.osBuild, languages: languages)
        let stored = store.current.text.warmed
        let state = warmup?.changed(to: record) ?? WarmupState.initial(stored: stored, current: record)
        guard state.shouldStart else {
            warmup = state
            return
        }
        warmup = state.started()
        logger.notice("Text recognition warm-up started")
        do {
            try await text.warmUp(languages)
            warmup = warmup?.finished()
            store.update { $0.with(\.text.warmed, record) }
            logger.notice("Text recognition warm-up done")
        } catch {
            warmup = warmup?.interrupted()
            logger.error("Text recognition warm-up stopped: \(error.logDescription, privacy: .public)")
        }
    }

    /// Counts only: never the text, never a file name (D14).
    private func log(_ result: ActionResult, files: Int) {
        let kind = result.text.map { "text, \($0.characterCount) characters" } ?? (result.toast ?? "failed")
        logger.notice("Copy Text finished: \(files) files, \(kind, privacy: .public)")
    }

    /// The enabled keyboard layouts and input methods, by identifier (no permission needed).
    static func enabledInputSources() -> [String] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        }
    }
}

/// The working line of one job: progress that arrives after the result is dropped, so a late event never brings
/// the line back over the card.
@MainActor
final class WorkingLine {
    private let presenter: any ActionPresenter
    private let point: CGPoint?
    private var finished = false

    init(presenter: any ActionPresenter, point: CGPoint?) {
        self.presenter = presenter
        self.point = point
    }

    func show(_ line: String) {
        guard !finished else { return }
        presenter.showWorking(line, near: point)
    }

    func finish() { finished = true }
}
