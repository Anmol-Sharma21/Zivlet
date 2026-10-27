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
/// keyboards and this Mac's Vision; the working line with Cancel where the placement says; the job in the worker
/// (`TextService`); the clipboard; with ⌥ one `.txt` per input, written off the main thread; then the text card (with
/// notes for files not read, a refused clipboard or files not saved), "No text found" or the error's sentence. The
/// card's buttons copy again, save the files, or open Show All. After onboarding it warms text recognition up once
/// per OS build and language set (D-M6-16), one warm-up at a time. The text itself is never logged or stored (D14).
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
    /// A warm-up is running; another is not started beside it.
    private var warmingUp = false
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
        let line = WorkingLine(presenter: presenter, point: point)
        let task = Task { @MainActor in
            let result = await self.copyText(urls, optionHeld: optionHeld, line: line)
            line.finish()
            presenter.show(result, near: point)
            self.log(result, files: urls.count)
            self.startWarmUpIfNeeded()
            return result
        }
        line.attach(task)
        return task
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
            let plan = try await languages()
            line.show(ToolWiringModel.working(warmupDone: plan.warmed, fraction: nil))
            let recognized = try await text.copyText(urls, languages: plan.languages) { fraction in
                Task { @MainActor in line.show(ToolWiringModel.working(warmupDone: plan.warmed, fraction: fraction)) }
            }
            return await finish(recognized, sources: urls, optionHeld: optionHeld, skipsHindi: plan.skipsHindi)
        } catch {
            if error == .cancelled {
                logger.notice("Copy Text cancelled")
            } else {
                logger.error("Copy Text failed: \(error.logDescription, privacy: .public)")
            }
            return ToolWiringModel.failure(error)
        }
    }

    /// The clipboard first; with ⌥ the files; then the card. A refused clipboard or a file not saved becomes a note
    /// on the card, so minutes of recognition are never thrown away.
    private func finish(_ recognized: RecognizedText, sources: [URL], optionHeld: Bool, skipsHindi: Bool) async
        -> ActionResult
    {
        guard !recognized.isEmpty else {
            return ToolWiringModel.result(recognized, sources: sources, skipsHindi: skipsHindi)
        }
        var copied = true
        if case .failed = clipboard.copyText(recognized.text) {
            copied = false
            logger.error("Copy Text: the clipboard refused the text")
        }
        var delivery = TextDelivery(copied: copied)
        if ToolWiringModel.writesFiles(optionHeld: optionHeld) {
            let files = zip(sources, recognized.perFile).filter { !$0.1.isEmpty }.map {
                TextFile(source: $0.0, text: $0.1.text)
            }
            delivery = await TextSaver.save(files, fallbackFolder: fallbackFolder, copied: copied)
        }
        return ToolWiringModel.result(recognized, sources: sources, delivery: delivery)
    }

    private func pressed(_ button: TextResultButton, _ outcome: TextOutcome) {
        switch button {
        case .copyAgain:
            if case .failed(let error) = clipboard.copyText(outcome.fullText) {
                actions.present(ActionResult(.failed(error)), near: nil)
            }
        case .saveText:
            Task { @MainActor in
                let delivery = await TextSaver.save(outcome.text.files, fallbackFolder: fallbackFolder, copied: true)
                actions.present(ToolWiringModel.saved(delivery), near: nil)
            }
        case .showAll:
            preview.show(TextPreviewModel(title: outcome.windowTitle, text: outcome.fullText))
        }
    }

    private var fallbackFolder: URL { URL(fileURLWithPath: store.current.output.fallbackFolder) }

    /// What one job reads with: the ordered languages, whether the warm-up is done for them on this OS build, and
    /// whether Hindi was wanted but this Mac's Vision has none.
    private struct LanguagePlan {
        let languages: [LanguageTag]
        let warmed: Bool
        let skipsHindi: Bool
    }

    private func languages() async throws(TextError) -> LanguagePlan {
        let capabilities = try await currentCapabilities()
        let (preferred, sources) = (Locale.preferredLanguages, Self.enabledInputSources())
        let choice = choiceOverride ?? store.current.text.language
        let languages = RecognitionLanguages.defaults(
            preferred: preferred, inputSources: sources, choice: choice, capabilities: capabilities)
        let record = TextWarmupRecord(osBuild: capabilities.osBuild, languages: languages)
        let skipsHindi = RecognitionLanguages.skipsHindi(
            preferred: preferred, inputSources: sources, choice: choice, capabilities: capabilities)
        return LanguagePlan(languages: languages, warmed: store.current.text.warmed == record, skipsHindi: skipsHindi)
    }

    private func currentCapabilities() async throws(TextError) -> VisionCapabilities {
        if let capabilities { return capabilities }
        let fetched = try await text.capabilities()
        capabilities = fetched
        return fetched
    }

    /// Runs the warm-up when the state says so; a failure stays needed until the next launch (no loop). One runs at
    /// a time: a change of languages while one runs is picked up when it ends (the next job or launch), and a
    /// finished warm-up stores its record only if it is still the current one.
    private func warmUpIfNeeded() async {
        guard store.current.onboarding.completed, !warmingUp else { return }
        let plan: LanguagePlan
        let capabilities: VisionCapabilities
        do {
            capabilities = try await currentCapabilities()
            plan = try await languages()
        } catch {
            return logger.error("Text recognition warm-up not started: \(error.logDescription, privacy: .public)")
        }
        let record = TextWarmupRecord(osBuild: capabilities.osBuild, languages: plan.languages)
        let stored = store.current.text.warmed
        let state = warmup?.changed(to: record) ?? WarmupState.initial(stored: stored, current: record)
        guard state.shouldStart else {
            warmup = state
            return
        }
        warmup = state.started()
        warmingUp = true
        defer { warmingUp = false }
        logger.notice("Text recognition warm-up started")
        do {
            try await text.warmUp(plan.languages)
            warmup = warmup?.finished()
            if (try? await languages().languages) == plan.languages {
                store.update { $0.with(\.text.warmed, record) }
            }
            logger.notice("Text recognition warm-up done")
        } catch {
            warmup = warmup?.interrupted()
            logger.error("Text recognition warm-up stopped: \(error.logDescription, privacy: .public)")
        }
    }

    /// Counts only: never the text, never a file name (D14). The error's kind is logged where it is caught.
    private func log(_ result: ActionResult, files: Int) {
        logger.notice("Copy Text finished: \(files) files, \(Self.logKind(result), privacy: .public)")
    }

    static func logKind(_ result: ActionResult) -> String {
        switch result {
        case .text(let outcome):
            "text, \(outcome.characterCount) characters, \(outcome.notes.isEmpty ? "no" : "with") notes"
        case .cancelled: "cancelled"
        case .failed: "failed"
        case .partial: "no text, some files not read"
        case .done(let toast, _, _): toast == ToolWiringModel.noText ? "no text" : "no text, Hindi missing"
        case .working: "working"
        }
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

/// The working line of one job and its Cancel. Progress that arrives after the result (or a cancel) is dropped, so
/// a late event never brings the line back over the card; progress only moves forward (each event hops to the main
/// actor on its own, so an older percent can arrive late), and the line is drawn only when its words change (at
/// most once per percent).
@MainActor
final class WorkingLine {
    private let presenter: any ActionPresenter
    private let point: CGPoint?
    private var finished = false
    private var shown: WorkingStatus?
    private var task: Task<ActionResult, Never>?

    init(presenter: any ActionPresenter, point: CGPoint?) {
        self.presenter = presenter
        self.point = point
    }

    /// The job's task, which Cancel stops (TextService forwards it to the worker).
    func attach(_ task: Task<ActionResult, Never>) { self.task = task }

    func show(_ status: WorkingStatus) {
        guard !finished, status.line != shown?.line else { return }
        if let old = shown?.fraction, let new = status.fraction, new < old { return }
        shown = status
        presenter.showWorking(status, near: point) { [weak self] in self?.cancel() }
    }

    func cancel() {
        finished = true
        task?.cancel()
    }

    func finish() { finished = true }
}
