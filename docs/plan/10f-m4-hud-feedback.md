# 10f — M4 stream D, part 2: progress model, HUD, result card, mode switching, sound and haptics

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. Depends on D1 (settings)
and creates nothing that streams A–C need.

---

## Task D7 — `JobProgress` grows ETA, bytes and stages; 10 Hz, monotonic (G-3, P1-07 remainder)

| Field | Value |
|---|---|
| Goal | `JobProgress {stage, stageCount, fraction?, bytesWritten?, eta?}` (03a §4.5; D-M3-4 trimmed it to `fraction`). ffmpeg: `eta = (expected − out_time) / speed` when `speed > 0.01` and at least 2 s of output exist, else nil; `bytesWritten` from `total_size=`; unknown duration → `fraction = nil` + bytes (indeterminate bar). Image engine reports frames done / total. `ProgressSink` throttles to 10 Hz per job and never lets the item or batch fraction decrease. `BatchSnapshot` carries the per-item progress; batch weight = duration × pixels for video, bytes otherwise (10 §8.2) |
| 05 rows | P1-07 (ETA), P1-40 input, G-3 |

**Files:** modify `Sources/ZivletCore/Jobs/JobState.swift` (`JobProgress`), `Sources/EngineMedia/FFmpegProgress.swift`,
`Sources/EngineMedia/MediaEngine.swift`, `Sources/EngineImage/ImageEngine.swift`, `Sources/ZivletEngineKit/ProgressSink.swift`,
`Sources/ZivletRuntime/BatchSnapshot.swift`; tests `FFmpegProgressTests` (recorded transcript: `speed=2.0x`,
`out_time_us=4000000`, expected 10 s → eta 3 s; `speed=N/A` → nil; first 2 s → nil), `ProgressSinkTests` (100
updates in 50 ms → ≤ 2 delivered; a lower fraction after a higher one is clamped), `BatchSnapshotTests` (a 1 GB video
and a 1 KB audio file: the video dominates the batch fraction).

Commit `feat(runtime): progress with ETA, bytes and stages, throttled and monotonic`.

---

## Task D8 — Progress HUD to spec; HUD moves into `ZivletUI` (P1-40)

| Field | Value |
|---|---|
| Goal | Move `App/ResultHUD.swift` into `Sources/ZivletUI/HUD/` (`ResultHUD`, `ResultHUDView`, `HUDModel`) so it is testable; `App/` keeps only wiring. Working state: title "Converting to <EXT>" (one target) / "Converting <n> files" (*new*, mixed targets cannot happen in one drop, kept for safety); line "name · i of n · pct%" with ETA appended as "· about 1 min left" (*new*) when known; indeterminate bar + "12.4 MB written" (*new*) when the fraction is unknown; Cancel. 360 × 108 non-activating panel near the pointer clamped 12 pt inside the screen; each concurrent batch's panel cascades 24 pt down-right (03a §4.5); visible ≤ 50 ms after drop — `OSSignposter` interval `drop→hud` (category `hud`), asserted in a test with the panel created off-screen |
| 05 rows | P1-40 |
| Sources | 03a §4.5, 05 P1-40 |

**Files:** move/modify as above; create `Sources/ZivletUI/HUD/HUDLayout.swift` (pure: anchor, clamp, cascade),
`Tests/ZivletUITests/HUDLayoutTests.swift`, `Tests/ZivletUITests/HUDCopyTests.swift`,
`Tests/ZivletUITests/HUDTimingTests.swift`.

### D8.1 Failing tests first

```swift
@Suite("HUD layout (P1-40, 03a §4.5)")
struct HUDLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func anchorsNearThePointerInsideTheScreen() {
        let frame = HUDLayout.frame(anchor: CGPoint(x: 1430, y: 5), index: 0, screen: screen)
        #expect(frame.size == CGSize(width: 360, height: 108))
        #expect(frame.maxX <= screen.maxX - 12 && frame.minY >= screen.minY + 12)
    }

    @Test func concurrentBatchesCascade24Points() {
        let a = HUDLayout.frame(anchor: CGPoint(x: 400, y: 400), index: 0, screen: screen)
        let b = HUDLayout.frame(anchor: CGPoint(x: 400, y: 400), index: 1, screen: screen)
        #expect(b.minX - a.minX == 24 && a.minY - b.minY == 24)
    }
}

@Suite("HUD copy (P1-40)")
struct HUDCopyTests {
    @Test func workingLineHasNameIndexCountPercentAndETA() {
        let line = HUDCopy.working(name: "clip.mov", index: 2, count: 5, fraction: 0.42, eta: .seconds(70),
            bytes: nil)
        #expect(line == "clip.mov · 2 of 5 · 42% · about 1 min left")
    }

    @Test func unknownDurationShowsBytes() {
        #expect(HUDCopy.working(name: "a.wav", index: 1, count: 1, fraction: nil, eta: nil, bytes: 12_400_000)
            == "a.wav · 12.4 MB written")
    }

    @Test func titleNamesTheTarget() { #expect(HUDCopy.title(target: .webm) == "Converting to WEBM") }
}

@Suite("HUD appears quickly (P1-40: ≤ 50 ms)")
@MainActor
struct HUDTimingTests {
    @Test func firstFrameWithin50ms() {
        let hud = ResultHUD(screens: { [CGRect(x: -5000, y: -5000, width: 1440, height: 900)] })
        let start = ContinuousClock.now
        hud.prepare(near: CGPoint(x: -4000, y: -4000))
        hud.show(Fx.snapshot(submitted: 1))
        #expect(hud.isVisible)
        #expect(ContinuousClock.now - start < .milliseconds(50))
    }
}
```

### D8.2–D8.5

RED: `cannot find 'HUDLayout'` (and the module move breaks `App/` imports until done). GREEN: `swift test --filter
ZivletUITests`, `make app`. Commits `refactor(ui): move the result HUD into ZivletUI` and `feat(ui): progress HUD with
ETA, bytes, cascade and a 50 ms appearance budget`.

---

## Task D9 — Result card: thumbnail, sizes, Open, Copy, drag-out, details, Retry (P1-41, G-3, G-10)

| Field | Value |
|---|---|
| Goal | Done state: thumbnail of the first output (`QLThumbnailGenerator`, 64 pt, async, placeholder icon until ready), "photo.png · 2.1 MB → 640 KB" (before → after, `ByteCountFormatter` file style), buttons Undo, Reveal, Open (default app), Copy (writes the output file URLs, C2), and the thumbnail is a drag source (`NSDraggingSource`, file URLs of all outputs). Success card stays 4 s and is held while hovered (`NSTrackingArea`); failures stay until closed. Errors: reason sentence (`JobErrorCopy`), "Show Details" disclosure with the stderr tail (private: never logged publicly; selectable text), Retry (re-submits the failed items of that batch to the same target). Notes on the card: Downloads fallback "Saved to Downloads because the original folder is read-only." (*new*, G-10), alpha flattened, first frame only, SVG raster in PDF (B3), long GIF (B6). Undo results keep the M3 sentences |
| 05 rows | P1-41, G-3 (thumbnail, size, drag-out, 4 s hold), G-10 (announce fallback) |
| Sources | 03a §4.5, 01-prd §5.8 |

**Files:** create `Sources/ZivletUI/HUD/ResultCard.swift`, `ResultCardModel.swift` (pure: which buttons, which
notes, hold timer state), `ThumbnailLoader.swift`, `Tests/ZivletUITests/ResultCardModelTests.swift`,
`Tests/ZivletUITests/ResultCardSnapshotTests.swift`; modify `Sources/ZivletRuntime/BatchPresentation.swift` (sizes,
notes, fallback flag from `JobRequestFactory`), `Sources/ZivletRuntime/ConversionService.swift` (`retry(batch:)`).

### D9.1 Failing tests first

```swift
@Suite("Result card model (P1-41)")
struct ResultCardModelTests {
    @Test func successOffersUndoRevealOpenCopyAndShowsSizes() {
        let model = ResultCardModel(Fx.finished(outputs: [("photo.png", before: 2_100_000, after: 640_000)]))
        #expect(model.buttons == [.undo, .reveal, .open, .copy])
        #expect(model.sizeLine == "photo.png · 2.1 MB → 640 KB")
        #expect(model.lingers == .seconds(4) && model.holdsWhileHovered)
    }

    @Test func failureOffersDetailsAndRetryAndStays() {
        let model = ResultCardModel(Fx.failed(error: .processFailed(status: 1, stderrTail: "boom")))
        #expect(model.buttons == [.showDetails, .retry, .close])
        #expect(model.lingers == nil)
        #expect(model.details == "boom")
    }

    @Test func downloadsFallbackIsAnnounced() {
        let model = ResultCardModel(Fx.finished(outputs: [("a.png", before: 1, after: 1)], usedFallbackFolder: true))
        #expect(model.notes.contains("Saved to Downloads because the original folder is read-only."))
    }

    @Test func hoverHoldsAndLeavingRestartsTheTimer() {
        var timer = LingerTimer(duration: .seconds(4))
        timer = timer.started(at: .seconds(0)).hovered(at: .seconds(3))
        #expect(!timer.expired(at: .seconds(10)))
        #expect(timer.unhovered(at: .seconds(10)).expired(at: .seconds(14)))
    }
}
```

Plus an end-to-end check through the DEBUG demo: `make convert-demo FILE=… TO=png` prints the card's size line in the
`notice` log (`Result card: photo.png · 2.1 MB → 640 KB`) so automation can see what a person would.

05 asks for an XCUITest with a fixture job. XCUITest drives the UI through Accessibility and asks the user to allow
automation on first run, which this unattended environment cannot grant; the plan adds the UI test target
(`ZivletUITestsApp`, `-UITestFixture <dir>` launch argument that shows the card for a canned batch) and records it as
owner-run (O-6) until a CI runner has the permission (D-M4-14).

### D9.2–D9.5

RED: missing types. GREEN: `swift test --filter ZivletUITests`. Commits `feat(ui): result card with thumbnail,
sizes, open, copy and drag-out`, `feat(ui): failure details and retry`, `feat(runtime): announce the Downloads
fallback on the card`, `test(ui): UI test target with a fixture batch (owner-run)`.

---

## Task D10 — Mode switching and cancel paths: tests for the remaining rules + QA checklist (P1-42)

| Field | Value |
|---|---|
| Status found in the audit | Done in code: ⇧/⌘/⌃ switch in place with `glassEffectID` morph, Reduce Motion fades, re-tap closes (D-2, `retapClosesWheel`), hub drop snaps back, Esc hot key registered only while visible, Space change hides (M1/M2). Missing: a test that the highlight resets on a mode switch, and the checklist `docs/plan/qa/trigger.md` that 05 names as acceptance |
| Goal | Add the missing unit test; write the checklist (rows from 03a §1.4 transitions T1…T18 that need a person: modifier taps during a live Finder drag, Esc during a drag, full-screen Space switch, two displays) for the owner (O-6) |

**Files:** `Tests/ZivletWheelTests/WheelStoreTests.swift` (switching mode clears `highlighted` and re-runs the intro
in Reduce Motion as an 80 ms fade), create `docs/plan/qa/trigger.md`.

Commit `test(wheel): highlight resets on mode switch` and `docs: trigger QA checklist for real drags`.

---

## Task D11 — Sound and haptics: settings gate, licence record (P1-43)

| Field | Value |
|---|---|
| Status found in the audit | The tick is synthesized in code (`ToneSynth`: 1,318.5 Hz sine, 24 ms, 1 ms attack, 6 ms decay), played through System Sound Services at most once per 35 ms (stricter than 05's 30 ms), silent when the system UI-sound setting is off; haptics on highlight change. Missing: user toggles (D1/D2 add Sound and Haptics separately, per 03a §2.7, which is newer than 05's "one setting gates both") and the licence record |
| Goal | Tests that the store values reach `SystemWheelFeedback` (D2 covers wiring); add to `THIRD_PARTY_NOTICES.md` under "Present": "Highlight tick: synthesized at runtime by Zivlet's own code (`ToneSynth`); no recorded sample is bundled." |

Commit `docs: record that the highlight tick is synthesized by Zivlet`.
