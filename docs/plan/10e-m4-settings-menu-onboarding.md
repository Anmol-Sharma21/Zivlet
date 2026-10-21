# 10e — M4 stream D, part 1: settings store, Settings window, menu bar, launch at login, onboarding

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6.

Two new SwiftPM targets: `ZivletSettings` (strict, pure values + a `UserDefaults`-backed store, no AppKit) and
`ZivletUI` (shell, main-actor default isolation like `ZivletWheel`: Settings window, menu model, onboarding, and — in
10f — the HUD moved out of `App/`). Both are added to `GATED_MODULES` in `Scripts/coverage.sh`. SwiftUI views are
covered the way M2 covered the wheel: `ImageRenderer` snapshots of each pane plus model tests.

---

## Task D1 — `ZivletSettings`: versioned, validated settings values (P1-46 base, 03b §8.1)

| Field | Value |
|---|---|
| Goal | `Settings` = immutable value with Phase 1 groups: `trigger` (`TriggerBindings` ⇧/⌘/⌃, `retapClosesWheel` true, `honorsModifierHeldAtDragStart` false, `paused` false), `feedback` (`sound` true, `haptics` true, `theme` `.glass`), `output` (`revealResults` true, `fallbackFolder` `~/Downloads`), `actions` (`terminal` `com.apple.Terminal`), `updates` (`automaticChecks` true, `automaticDownloads` false), `onboarding` (`completed` false, `page` 0, `practiceDragsLeft` 3). `SettingsStore` loads one JSON blob per group from `UserDefaults` (keys `settings.<group>.v1`), validates each group (bindings must be three distinct single modifiers; folder must be an absolute existing directory; terminal id must match `^[A-Za-z0-9.-]+$`) and replaces an invalid group with its default plus one `.error` log line naming the group (no value logged). `update(_:)` takes a transform `(Settings) -> Settings` and persists only changed groups; changes are published as an `AsyncStream<Settings>`. Migration: the M3 key `ZivletRevealResults` is read once into `output.revealResults` and removed |
| 05 rows | P1-46, P1-43 (toggles) |
| Sources | 03b §8.1, 03a §2.7 ("Separate Sound and Haptics toggles, both default on"), 14 §3.2 |

**Files:** modify `Package.swift`; create `Sources/ZivletSettings/Settings.swift`, `SettingsStore.swift`,
`SettingsValidation.swift`, `Tests/ZivletSettingsTests/SettingsStoreTests.swift`.

### D1.1 Failing tests first

```swift
import Foundation
import Testing
import ZivletTrigger

@testable import ZivletSettings

@Suite("Settings store: defaults, validation, migration (D1, 03b §8.1)")
struct SettingsStoreTests {
    static func defaults() -> UserDefaults {
        let name = "zivlet-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func freshStoreHasTheDocumentedDefaults() {
        let settings = SettingsStore(defaults: Self.defaults()).current
        #expect(settings.feedback.sound && settings.feedback.haptics && settings.feedback.theme == .glass)
        #expect(settings.output.revealResults)
        #expect(settings.actions.terminal == "com.apple.Terminal")
        #expect(settings.trigger.bindings == .standard && settings.trigger.retapClosesWheel)
        #expect(!settings.onboarding.completed && settings.onboarding.practiceDragsLeft == 3)
    }

    @Test func updatesPersistAcrossStores() {
        let defaults = Self.defaults()
        SettingsStore(defaults: defaults).update { $0.with(\.feedback.sound, false) }
        #expect(!SettingsStore(defaults: defaults).current.feedback.sound)
    }

    @Test func anInvalidGroupFallsBackToItsDefaultOnly() {
        let defaults = Self.defaults()
        defaults.set(Data(#"{"terminal":"bad id; rm -rf"}"#.utf8), forKey: "settings.actions.v1")
        defaults.set(Data(#"{"sound":false,"haptics":true,"theme":"solid"}"#.utf8), forKey: "settings.feedback.v1")
        let settings = SettingsStore(defaults: defaults).current
        #expect(settings.actions.terminal == "com.apple.Terminal")
        #expect(!settings.feedback.sound && settings.feedback.theme == .solid)
    }

    @Test func duplicateModifierBindingsAreRefused() {
        let defaults = Self.defaults()
        defaults.set(Data(#"{"bindings":{"convert":"shift","tools":"shift","actions":"control"},"#.utf8
            + #""retapClosesWheel":true,"honorsModifierHeldAtDragStart":false,"paused":false}"#.utf8),
            forKey: "settings.trigger.v1")
        #expect(SettingsStore(defaults: defaults).current.trigger.bindings == .standard)
    }

    @Test func theM3RevealKeyIsMigratedOnce() {
        let defaults = Self.defaults()
        defaults.set(false, forKey: "ZivletRevealResults")
        #expect(!SettingsStore(defaults: defaults).current.output.revealResults)
        #expect(defaults.object(forKey: "ZivletRevealResults") == nil)
    }

    @Test func changesAreStreamed() async {
        let store = SettingsStore(defaults: Self.defaults())
        var iterator = store.changes.makeAsyncIterator()
        store.update { $0.with(\.feedback.haptics, false) }
        #expect(await iterator.next()?.feedback.haptics == false)
    }
}
```

### D1.2 Run, expect failure

`swift test --filter ZivletSettingsTests` → `error: no such module 'ZivletSettings'`.

### D1.3 Implement

`Settings.with(_:_:)` returns a copy with one key path changed (immutable updates, owner rule). `fallbackFolder`
stores a path string, validated on load and on update; `~` expanded only at load. The store is `@MainActor final
class` (it is read by AppKit adapters); values are `Sendable` structs.

### D1.4 Verify green / D1.5 Commit

`swift test --filter ZivletSettingsTests`. Commit `feat(settings): versioned, validated settings store with
defaults and migration`.

---

## Task D2 — Settings drive the trigger, wheel, feedback, reveal and fallback folder

| Field | Value |
|---|---|
| Goal | The composition root reads `SettingsStore.current` at launch and applies `changes`: `TriggerConfig` from `trigger` (bindings, retap, held-at-start, `paused` stops the host: `trigger.stop()` / `start()`), `WheelAppearance.theme`, `SystemWheelFeedback(hapticsEnabled:)` and `TickSound(isEnabled: sound && systemUISounds)`, reveal from `output.revealResults`, `JobRequestFactory` fallback folder from `output.fallbackFolder` (today hard-coded `~/Downloads`) |
| 05 rows | P1-46, P1-43, FR-17 |

**Files:** modify `App/AppDelegate.swift` (stays a composition root; new `App/SettingsWiring.swift` holds the
apply-functions so `AppDelegate` stays under 200 lines), `Sources/ZivletRuntime/JobRequestFactory.swift`
(`fallbackFolder` parameter), `Sources/ZivletWheel/WheelFeedback.swift` (`TickSound` gets a settable
`enabled` through a new immutable `FeedbackSettings` value passed on change), tests in `ZivletRuntimeTests`
(fallback folder used when the source folder is read-only) and `ZivletWheelTests` (feedback with sound off plays
nothing; haptics off performs nothing).

Commit `feat(app): settings drive trigger bindings, feedback, theme, reveal and the fallback folder`.

---

## Task D3 — Settings window: General, Updates, Advanced (P1-46)

| Field | Value |
|---|---|
| Goal | `SettingsWindowController` (`NSWindowController` + `NSTabViewController(.toolbar)`, SwiftUI `Form(.grouped)` panes, 14 §3.2). **General:** wheel keys (three pickers ⇧ ⌘ ⌃ ⌥ with exclusion: choosing a modifier already used swaps the two, so the three stay distinct), sound, haptics, theme (Glass / Solid), launch at login (D5), reveal results in Finder, fallback folder (Choose…), terminal (installed terminals from `TerminalCatalog`). **Updates** (F2): automatic checks, automatic downloads, "Check Now", channel line "Stable". **Advanced:** helper versions (`ffmpeg -version` first line, libwebp version, resvg version), "Copy Diagnostics" (E5), "Acknowledgements…" (opens `Contents/Resources/Licenses/index.html`). Re-opening the app (double-click while running) opens Settings (03b §8.3) |
| 05 rows | P1-46 |
| Sources | 03b §8.1 panes (Formats, Tools, Keyboard & Automation panes are P3-32) |

**Files:** create `Sources/ZivletUI/Settings/SettingsWindowController.swift`, `GeneralPane.swift`, `UpdatesPane.swift`,
`AdvancedPane.swift`, `BindingPicker.swift` (pure swap logic in `BindingEditing.swift`),
`Tests/ZivletUITests/BindingEditingTests.swift`, `Tests/ZivletUITests/SettingsPaneSnapshotTests.swift`.

### D3.1 Failing tests first

```swift
@Suite("Binding editing keeps three distinct modifiers (D3)")
struct BindingEditingTests {
    @Test func choosingAUsedModifierSwapsTheTwo() {
        let edited = BindingEditing.set(.command, for: .convert, in: .standard)   // ⇧/⌘/⌃ → ⌘/⇧/⌃
        #expect(edited.modifier(for: .convert) == .command && edited.modifier(for: .tools) == .shift)
        #expect(Set(WheelMode.allCases.map(edited.modifier(for:))).count == 3)
    }

    @Test func choosingAFreeModifierJustReplaces() {
        let edited = BindingEditing.set(.option, for: .actions, in: .standard)
        #expect(edited.modifier(for: .actions) == .option && edited.modifier(for: .tools) == .command)
    }
}

@Suite("Settings panes render (D3)")
@MainActor
struct SettingsPaneSnapshotTests {
    @Test(arguments: SettingsPane.allCases)
    func everyPaneRendersWithDefaults(pane: SettingsPane) throws {
        let image = try #require(ImageRenderer(content: pane.view(model: .preview)).nsImage)
        #expect(image.size.width >= 480 && image.size.height >= 200)
    }

    @Test func generalPaneListsOnlyInstalledTerminals() {
        let model = SettingsModel.preview(installedTerminals: [.terminal, .ghostty])
        #expect(model.terminalChoices.map(\.name) == ["Terminal", "Ghostty"])
    }
}
```

### D3.2–D3.5

RED: missing module/types. GREEN: `swift test --filter ZivletUITests`; `make app`, open Settings from the status menu
(manual look, screenshot to `build/settings-*.png` via `screencapture -l` in a DEBUG demo argument
`-ZivletDemoSettings <pane>`). Commit `feat(ui): Settings window with General, Updates and Advanced panes`.

---

## Task D4 — Menu bar (P1-46, G-7 recent results)

| Field | Value |
|---|---|
| Goal | Pure `MenuModel.make(state:)` → `[MenuEntry]`, rebuilt in `menuNeedsUpdate`: (1) state line "Zivlet is ready" / "Working on N" / "Paused" (*new*); (2) shortcut summary `⇧: Convert · ⌘: Tools · ⌃: Actions` from current bindings (disabled); (3) active batches (name middle-truncated to 38 characters keeping the extension, percent, Cancel); (4) "Recent Results" submenu from `UndoHistory` entries (≤ 10): Reveal, Undo; (5) Settings… ⌘, · Practice… · Pause Zivlet / Resume Zivlet · Check for Updates… · About Zivlet · Quit Zivlet ⌘Q. The DEBUG demo submenu stays, DEBUG only |
| 05 rows | P1-46, P1-15/G-7 (status-menu Recent results) |
| Sources | 03b §8.3, 03a §4.7 surfaces |

**Files:** create `Sources/ZivletUI/Menu/MenuModel.swift`, `Sources/ZivletUI/Menu/NameTruncation.swift`,
`Tests/ZivletUITests/MenuModelTests.swift`; modify `App/StatusMenu.swift` (renders `MenuEntry` values; actions call
closures provided by `AppDelegate`).

### D4.1 Failing tests first

```swift
@Suite("Menu model (D4, 03b §8.3)")
struct MenuModelTests {
    @Test func idleMenuHasTheFixedItemsInOrder() {
        let titles = MenuModel.make(state: .idle(bindings: .standard)).map(\.title)
        #expect(titles == ["Zivlet is ready", "⇧: Convert · ⌘: Tools · ⌃: Actions", "—", "Settings…", "Practice…",
            "Pause Zivlet", "Check for Updates…", "—", "About Zivlet", "Quit Zivlet"])
    }

    @Test func workingShowsOneRowPerBatchAndTheCount() {
        let state = MenuState(bindings: .standard, paused: false,
            batches: [Fx.batch("holiday video.mov", percent: 40), Fx.batch("a.wav", percent: 90)], recent: [])
        let entries = MenuModel.make(state: state)
        #expect(entries.first?.title == "Working on 2")
        #expect(entries.contains { $0.title == "holiday video.mov — 40%" && $0.action == .cancel(Fx.batchID(0)) })
    }

    @Test(arguments: [
        ("short.png", "short.png"),
        ("a very long file name that keeps going and going.mov", "a very long file nam…going and going.mov"),
    ])
    func namesAreMiddleTruncatedTo38KeepingTheExtension(name: String, shown: String) {
        #expect(NameTruncation.middle(name, limit: 38) == shown)
        #expect(NameTruncation.middle(name, limit: 38).count <= 38)
    }

    @Test func pausedChangesTheStateLineAndToggle() {
        let titles = MenuModel.make(state: .idle(bindings: .standard, paused: true)).map(\.title)
        #expect(titles.first == "Paused" && titles.contains("Resume Zivlet"))
    }

    @Test func recentResultsListsAtMostTen() {
        let state = MenuState(bindings: .standard, paused: false, batches: [], recent: (0..<14).map(Fx.recent))
        let recent = MenuModel.make(state: state).first { $0.title == "Recent Results" }
        #expect(recent?.children.count == 10)
    }
}
```

The exact middle-truncation output above is illustrative; the test asserts the rule (prefix + `…` + suffix that
keeps the extension, total ≤ 38) — fix the literal when the implementation's split point is chosen.

### D4.2–D4.5

RED: missing types. GREEN: `swift test --filter MenuModelTests`. Commit `feat(ui): status menu with state, active
batches, recent results, pause and settings`.

---

## Task D5 — Launch at login with `SMAppService.mainApp` (P1-46)

| Field | Value |
|---|---|
| Goal | `LoginItem` behind `protocol LoginItemService { var status: SMAppService.Status { get }; func register() throws; func unregister() throws }`. The General toggle shows the live status; `.requiresApproval` shows "Allow Zivlet in System Settings › General › Login Items." with a button calling `SMAppService.openSystemSettingsLoginItems()`; errors are shown in the pane in Zivlet's words ("Zivlet couldn't change its login item.") and logged with the error code. Onboarding page 6 sets it on by default (D6) |
| 05 rows | P1-46 |
| Sources | 03b §8.4, 14 §3.4 |

**Files:** create `Sources/ZivletUI/Settings/LoginItem.swift`, `Tests/ZivletUITests/LoginItemTests.swift` (fake
service: toggle on → `register()` once; status `.requiresApproval` → model exposes the approval message; `register`
throwing → model error text, toggle reverts).

Commit `feat(ui): launch at login through SMAppService`. Real registration is checked by the owner in O-6 (it needs
an installed, signed app in `/Applications`).

---

## Task D6 — Onboarding and practice (P1-47)

| Field | Value |
|---|---|
| Goal | `OnboardingFlow` (pure, resumable): pages `welcome, practiceConvert, practiceToolsActions, keyboard, privacy, loginAndUpdates, location` (03b §8.2; the keyboard page in Phase 1 shows only "Services and a global shortcut arrive later" — *new* copy — because keyboard mode is P2), `next`/`back`, `completed` written only by Finish, quitting resumes at the stored page. **Practice:** the window shows a sample file the user drags; the real trigger and wheel open (self-test); success = a `WheelSelection` arrives while the practice page is up (no conversion is run: the practice handler swallows it and shows "That's it." — *new*). The sample file is made by Zivlet at first run (`OnboardingSample.make(in:)` draws a 512 × 320 PNG with Core Graphics: a gradient and the word "Practice"; no bundled image, no third-party asset) into `~/Library/Application Support/Zivlet/Practice/practice.png`. Key caps come from current bindings. **Privacy page:** explains that macOS asks once per protected folder (Desktop, Documents, Downloads, removable volumes) when a file there is first converted, using the table from 03b §8.2 page 5; buttons "Grant now" are omitted in Phase 1 (they need spike P-P1, owner hardware). **Location page:** if `Bundle.main.bundlePath` starts with `/Volumes/` or contains `AppTranslocation`, offer "Move to Applications" (copies to `/Applications`, relaunches; failure message in Zivlet's words). **Coach:** for the first 3 real drags after onboarding, a small key legend appears beside the wheel ("⇧ Convert · ⌘ Tools · ⌃ Actions"), counted down in `onboarding.practiceDragsLeft` |
| 05 rows | P1-47 **[QA]** (5 of 5 testers finish unaided: owner step O-6) |
| Sources | 03b §8.2, 14 §3.3 |

**Files:** create `Sources/ZivletUI/Onboarding/OnboardingFlow.swift`, `OnboardingWindow.swift`,
`OnboardingPages.swift`, `OnboardingSample.swift`, `PracticeCoordinator.swift`, `KeyLegend.swift`;
`Tests/ZivletUITests/OnboardingFlowTests.swift`, `OnboardingSampleTests.swift`, `OnboardingSnapshotTests.swift`;
modify `App/AppDelegate.swift` (show onboarding when `!completed`; route selections to the practice coordinator while
it is active; Practice… menu item reopens page 2).

### D6.1 Failing tests first

```swift
@Suite("Onboarding flow (P1-47, 03b §8.2)")
struct OnboardingFlowTests {
    @Test func walksForwardAndBackWithinBounds() {
        let flow = OnboardingFlow(page: .welcome)
        #expect(flow.back().page == .welcome)
        #expect(flow.next().next().page == .practiceToolsActions)
        #expect(OnboardingFlow(page: .location).next().page == .location)
    }

    @Test func onlyFinishCompletes() {
        let atEnd = OnboardingFlow(page: .location)
        #expect(!atEnd.next().isCompleted)
        #expect(atEnd.finish().isCompleted)
    }

    @Test func resumesAtTheStoredPage() {
        #expect(OnboardingFlow(storedPage: 3).page == .keyboard)
        #expect(OnboardingFlow(storedPage: 99).page == .welcome)
    }

    @Test func practiceSucceedsOnTheFirstSelectionOfTheTaughtMode() {
        let practice = PracticeState(teaching: .convert)
        #expect(practice.receiving(Fx.selection(mode: .tools)).outcome == .wrongMode(expected: .convert))
        #expect(practice.receiving(Fx.selection(mode: .convert)).outcome == .done)
    }
}

@Suite("Practice sample is Zivlet's own drawing (P1-47)")
struct OnboardingSampleTests {
    @Test func makesAReadablePNGOnce() throws {
        let dir = try TempDir()
        let first = try OnboardingSample.make(in: dir.url)
        let again = try OnboardingSample.make(in: dir.url)
        #expect(first == again)
        let source = try #require(CGImageSourceCreateWithURL(first as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        #expect(CGImageSourceGetCount(source) == 1)
    }
}
```

### D6.2–D6.5

RED: missing types. GREEN: `swift test --filter ZivletUITests`; `make app`, launch with `-ZivletResetOnboarding YES`
(DEBUG): the window appears; a real drag of the sample with ⇧ shows "That's it." (manual; owner O-6 for the 5-tester
usability bar). Commits `feat(ui): resumable onboarding flow`, `feat(ui): practice page with Zivlet's own sample
file`, `feat(ui): key legend for the first three drags`.
