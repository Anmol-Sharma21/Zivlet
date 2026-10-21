# 06 — M1 implementation plan: repo skeleton + pure core logic (TDD)

Date: 2026-10-20. Status: ready to execute. Milestone: **M1** of [05 §2](05-task-list.md).
This file is the index. The tasks are in six parts, each under 800 lines (the embedded, verified test code does not
fit in three):

| Part | Tasks |
|---|---|
| [06a](06a-m1-repo-formats.md) | 1 Repository bootstrap · 2 ZivletKit package skeleton · 3 Format registry |
| [06b](06b-m1-catalog-naming.md) | 4 Conversion, tool and action catalog · 5 OutputNamer |
| [06c](06c-m1-trigger.md) | 6 Modifier bindings and TriggerMachine |
| [06d](06d-m1-wheel.md) | 7 Wheel geometry, hit-testing and slice lists |
| [06e](06e-m1-media.md) | 8 EngineMedia argv planners |
| [06f](06f-m1-app-exit.md) | 9 XcodeGen app target and dev entry points · M1 exit check |

Inputs: [00-decisions](../design/00-decisions.md), [10-tech-strategy](../design/10-tech-strategy.md) ([challenge] notes win),
[11-media-engine](../design/11-media-engine.md), [01-prd](01-prd.md), [02-architecture](02-architecture.md),
[03a](03a-system-design-interaction.md), [03b](03b-system-design-engines.md), [04-tech-doc](04-tech-doc.md),
[05-task-list](05-task-list.md).

Clean-room rule: every value below is a behaviour or parameter from Zivlet's own docs. No code, assets, sounds, icons,
strings or screenshots from the reference app or from Open-Tangerine are used.

---

## 1. Verification status of this plan

Every code block in 06a–06f was compiled and run on 2026-10-20 on the dev Mac (macOS 27.0, Xcode 27.0, Swift 6.4,
XcodeGen 2.45.4) before this plan was written. The test code is the verified file, embedded verbatim.

| Check | Result |
|---|---|
| `swift test` in `Packages/ZivletKit` | 103 test functions (12 suites + 1 free function), 729 cases with parameterised arguments, all pass [critic3: re-run 2026-10-20 after the D4 and D15 edits; was 102 / 728] |
| Line coverage (`make coverage`) | ZivletCore 98 %, ZivletTrigger 100 %, ZivletWheelCore 99 %, EngineMedia 95 % |
| `swift format lint --strict` with the Task 1 `.swift-format` | 0 findings |
| `xcodegen generate` + `xcodebuild` Debug and Release | `** BUILD SUCCEEDED **`; app signed `flags=0x10002(adhoc,runtime)`, `LSUIElement = true` |
| Task-by-task replay (Tasks 2–8 in a fresh package: tests, run, sources, run) | Every RED step failed to compile as stated; every GREEN count matched; the final tree and `Package.swift` were identical to the reference |
| Largest file / longest function | 189 lines (a test file) / under 50 lines |

Implementation sections give the key types, signatures and data tables. Where the logic is subtle (trigger transitions,
hit-testing, argv order) the verified body is given in full. An engineer may write different bodies as long as the
tests pass and the rules in §4 hold.

---

## 2. Task index

| # | Task | Module | 05 rows | Part | Tests added |
|---|---|---|---|---|---|
| 1 | Repository bootstrap | Repo | P0-01 | 06a | shell checks |
| 2 | ZivletKit package skeleton | Package | P0-02 (M1 subset) | 06a | 5 smoke tests |
| 3 | Format registry (46 formats: 45 inputs, 39 outputs) | Core | P0-10 | 06a | 8 |
| 4 | Conversion catalog (275 pairs), 27 tools, 6 actions | Core | P0-12, P0-14 | 06b | 14 |
| 5 | OutputNamer | Core | P0-16 | 06b | 11 |
| 6 | TriggerMachine + bindings | Trigger | P0-21, P0-23 | 06c | 29 [critic3] |
| 7 | WheelGeometry, hit-test, slice lists per mode | WheelCore | P0-24, P0-25, P0-15 (slices) | 06d | 24 |
| 8 | EngineMedia argv planners (audio, video, GIF) | EngineKit, EngineMedia | P1-04/05/06 planner part, pulled forward | 06e | 17 |
| 9 | `project.yml` app target, Makefile, coverage gate | App, Repo | P0-04, P0-05, P0-06 | 06f | build check |

Dependency order is linear: each task assumes the previous ones are committed.

### 2.1 M1 rows of 05 not covered by this plan

05 §2 defines M1 as P0-01…P0-07, P0-10…P0-28. These rows are not in the nine tasks above and need a follow-on plan
(suggested `07-implementation-plan-m1b.md`) before M1 can be declared done:

| Row | Title | Why it is separate |
|---|---|---|
| P0-03 | Module dependency gate (`check-imports.sh`) | Script work; no new domain logic |
| P0-07 | PR CI workflow | Needs the self-hosted runner decision (P0-34, C-10) |
| P0-11 | Content sniffer (magic bytes) | Independent pure module; 03a §3.2 table is ready |
| P0-13 | Engine routes + phase tags (153 / 68 / 54) | Extends Task 4's catalog with 10 §4.2–4.12 data |
| P0-17…P0-20 | Job value types, error taxonomy, progress throttle, settings model | Core values for M2/M3 |
| P0-22 | JSON trigger traces | Task 6 uses an in-code trace DSL; JSON fixtures follow |
| P0-26…P0-28 | Panel placement, `WheelModel` reducer, drag-operation negotiation | Build on Task 7 |

---

## 3. Decisions taken while planning (conflicts between source docs)

| # | Topic | Sources disagree | This plan uses | Why |
|---|---|---|---|---|
| D1 | Pure wheel module | 02 §4.1 `ZivletWheelCore` (pure) + `ZivletWheel` (AppKit) vs 04 §4.1 one `ZivletWheel` with `defaultIsolation(MainActor)` | `ZivletWheelCore`, nonisolated | Geometry and slices test without MainActor; 02 is the architecture of record |
| D2 | `WheelMode`, `Point2D` home | 02 §7.6 puts `WheelMode` in Trigger, but 02 §4 says WheelCore imports only Core | Both in `ZivletCore/Shared` | Keeps the module graph legal; `Point2D` keeps pure modules free of CoreGraphics |
| D3 | Release grace | 02 §7.6 `lingerAfterExit`, a fixed linger | `releaseTimeout` **150 ms**, configurable | 03a §1.5 changes the 02 default; event-driven `dropHandled` ends it early. A test also runs a 300 ms value |
| D4 | Modifier held before the drag | 01-prd FR-4 / D-3, 05 D-3 / P0-23, 04 §6.5 "ignored" vs 02 §7.6 / 03a §1.5 `honorsModifierHeldAtDragStart = true` | [critic3] **`false` by default** (ignored until released and pressed again); `true` (parity) covered by a test | FR-4 is a P1 acceptance criterion; with ⌘ bound to Tools, parity would open the Tools wheel on every Finder ⌘-move drag. 02 and 03a now say `false`. Owner may flip the default (one line) |
| D5 | Mixed-family conversion selection | 05 P0-15 "nothing shared" empty state vs 03a §2.6 badged union | Badged union ("k of n") if ≤ 12 slots, else "These files can't share a format" | 03a §2.6 [06 P0-8] is the Zivlet design. [critic3] 01-prd FR-20, 05 D-1 / P0-15 and 02 §7.1 aligned to this; **[OWNER]** confirm at the P-W1 usability pass (03 open items) |
| D6 | Families | 02 §7.1 `family` + `mixingFamily` (8 cases incl. slides) | `FormatFamily` = 7 mixing families; `FormatCategory` = 11 pair categories (03a §3.1, 10 §4.13) | Matches the observed mixing behaviour and gives the per-family counts directly |
| D7 | `gz` role | 05 P0-10 lists gz as output-only | gz is input and output; canonical extension `tar.gz` | The 06b conversion table has a gz row; the archive naming rule (03a §4.4) writes `.tar.gz` |
| D8 | UTIs without a system declaration | — | `mkv` → `app.zivlet.matroska`, `srt` → `app.zivlet.subrip`, `rar` → `app.zivlet.rar` | `UTType(filenameExtension:)` returns `dyn.*` for them on macOS 27.0; they need `UTImportedTypeDeclarations` in P1 |
| D9 | Third-party packages in M1 | 02 §5.1 declares swift-subprocess and KeyboardShortcuts | None in M1; `ZivletEngineKit` holds only `Lane` | Each dependency arrives with its first user (P1-20, P1-46); M1 builds offline |
| D10 | ffmpeg prefix order | 05 P1-03 `-nostdin -hide_banner …` vs 03b §5.2 | 03b §5.2 order | 03b is the canonical argv; goldens compare whole argv |
| D11 | Cover art for ogg/opus/aiff | 03b §5.4: ogg/opus via ffmetadata, aiff spike M-6 | Dropped in M1 planners | Needs a Zivlet-written ffmetadata job file (P1-04) |
| D12 | libx264 fallback | 03b §5.5 `libx264 -preset medium -crf C` | Adds `-pix_fmt yuv420p` [new] | A 10-bit source would otherwise give High 10 H.264, which most players reject |
| D13 | Coverage source | 04 §6.8 `llvm-cov export` | `llvm-cov report` over **every** `.xctest` bundle | Observed: `swift test --show-codecov-path` JSON covered only some bundles under Xcode 27 |
| D14 | `docs/` in git | — | **[OWNER]** Task 1 commits only bootstrap files; `docs/design` + `docs/plan` follow in a `docs:` commit after review; only design and plan docs are committed | Design/plan docs are written to stand alone; publishing is an owner decision |
| D15 | Empty-state copy | An early 06d draft reused the reference app's status-pill wording verbatim, breaking the clean-room copy rule | [critic3] Fresh Zivlet strings in `EmptyReason.message` (06d 7c) | 01-prd line 15 and 04 §5 clean-room rule: no copy reused. Re-verified: 24/24 WheelCore tests, lint clean |

---

## 4. Conventions for every task

| Item | Rule |
|---|---|
| Shell setup | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` once per shell. `xcode-select` points at the CLT; never change it (04 §1.2) |
| Package commands | Run from `Packages/ZivletKit`: `swift test --filter <TestTarget>`; whole suite: `swift test` |
| Repo root | The repository root (`$REPO` below) |
| TDD loop | Write the test file(s) → run, see the expected failure → implement → run, see green → `swift format format -i -r Sources Tests` → commit |
| Expected RED | A missing type is a compile error, for example `error: cannot find 'FormatRegistry' in scope`. Swift Testing reports `✘ Test …` lines for assertion failures |
| Expected GREEN | `✔ Test run with N tests in M suites passed`. N counts `@Test` functions; parameterised cases are extra |
| Commits | `git commit -s -m "<type>(<scope>): <description>"`. DCO sign-off; no `Co-Authored-By` (04 §11) |
| Immutability | Model types use `let` properties only (04 §12). State changes build new values (`live.observing(…)`, `wheel.with(…)`). Local `var` only inside a function body (an RNG, a `Set` for de-duplication) |
| Size limits | Files 200–400 lines typical, 800 max; functions < 50 lines; nesting ≤ 3 |
| Errors | Typed throws at boundaries (`throws(MediaPlanError)`, `throws(NamingError)`, `throws(BindingError)`); nothing swallowed |
| Placeholders | Task 2 adds one placeholder file per target. The first real file in a target deletes its placeholder in the same commit |
| Citations | `03a §2.4` = plan/03a section; `10 §4.13` = design/10; `06b Task 4a` = plan/06b. [review] Code (Sources, Tests, App) cites only project-owned docs (plan/, design/) |

### 4.1 Final layout after Task 9

```text
Zivlet/
  .gitignore  .swift-format  LICENSE  README.md  CONTRIBUTING.md  Makefile  project.yml
  App/ZivletApp.swift
  Config/Base.xcconfig  Debug.xcconfig  Release.xcconfig  Zivlet.entitlements
  Scripts/env.sh  coverage.sh
  Packages/ZivletKit/
    Package.swift
    Sources/ZivletCore/{Formats,Catalog,Naming,Shared}/…
    Sources/ZivletTrigger/…          Sources/ZivletWheelCore/…
    Sources/ZivletEngineKit/Lane.swift
    Sources/EngineMedia/…
    Tests/TestSupport/SplitMix64.swift
    Tests/{ZivletCore,ZivletTrigger,ZivletWheelCore,ZivletEngineKit,EngineMedia}Tests/…
    Tests/EngineMediaTests/Goldens/*.txt
  docs/…
```

---

## 5. Definition of done for this plan

- [ ] Tasks 1–9 committed in order, each with its own conventional commit.
- [ ] `make test` exits 0; `make coverage` prints ≥ 80 % for ZivletCore, ZivletTrigger, ZivletWheelCore, EngineMedia.
- [ ] `make lint` exits 0.
- [ ] `make app` prints `** BUILD SUCCEEDED **`; the app launches as a menu-bar agent with no Dock icon.
- [ ] `git status` lists nothing except `docs/` while the owner decision D14 is pending; `Zivlet.xcodeproj`, `.build/`, `build/` are ignored.
- [ ] The §2.1 rows are planned before M1 is reported complete.
