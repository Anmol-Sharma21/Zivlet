# 18c — M6 Stream C: P2-01, `ZivletWorker.xpc` and the worker client

Part of [18-implementation-plan-m6](18-implementation-plan-m6.md). Conventions: index §6. Design:
[02-architecture](02-architecture.md) §2.1–§2.2 (process and IPC tables), §6.2 (cancellation), §7.4–§7.5 (client and
IPC); [03b](03b-system-design-engines.md) threat rows "parser exploit" and "XPC peer spoofing";
[design/10](../design/10-tech-strategy.md) §1–§2; [design/14](../design/14-app-platform.md) §5.4 and the signing
order. Prototype: index §3.1. Decisions: D-M6-2, D-M6-4, D-M6-5, D-M6-7, D-M6-9, D-M6-10, D-M6-18. Swift below is
specification-grade and was not compiled.

Shape of the change. The scheduler keeps running `[any Engine]`. For the engines that move (EngineImage now,
EngineVision in D8), the app holds a `RemoteEngine` that conforms to `Engine` and forwards `prepare`, `execute` and
`verify` through a `WorkerConnection`. The worker hosts the real engines behind a transport-free `WorkerService`.
Only two small files touch the XPC API: the worker's `main.swift` and the app's `XPCSessionFactory.swift`
(`@preconcurrency import XPC`, R4). Everything else is tested in `swift test` through a loopback transport that
JSON-encodes every message both ways, so a Codable mistake fails a unit test, not the smoke row.

New modules (strict settings, Foundation only unless noted), added to `GATED_MODULES` in `Scripts/coverage.sh`:

| Module | Depends on | Holds |
|---|---|---|
| `ZivletIPC` | `ZivletCore`, `ZivletEngineKit` | `Envelope`, `WorkerRequest`, `WorkerReply`, `WorkerEvent`, `WorkerProtocol.version`, `WorkerRequestValidator` |
| `ZivletWorkerCore` | `ZivletIPC`, `ZivletEngineKit`, `EngineImage` (and `EngineVision` from D8) | `WorkerService` actor, `IdleTimer`, job registry |

`ZivletRuntime` gains a dependency on `ZivletIPC` (and on `ZivletWorkerCore` only for the in-process fallback and the
loopback transport).

New strings (*new*): "This file made the engine crash." (05 P2-01's words, kept), "The converter stopped
unexpectedly. Trying again…" (working line during the retry), "Zivlet's converter is damaged. Reinstall Zivlet."
(signature check failed; `engineDamaged(.worker)` reuses the existing damaged-engine copy if it reads the same).

---

## Task C1 — `ZivletIPC`: the messages

| Field | Value |
|---|---|
| Goal | `Envelope<Body>` (`protocolVersion: Int`, `body`); `WorkerRequest`: `ping`, `capabilities`, `prepare(JobRequest, JobWorkspace)`, `execute(JobID, ExecutionPlan, outputByteLimit: Int64?)`, `verify(StagedOutput, ExecutionPlan)`, `cancel(JobID)`, and (D8) `recognizeText(TextJob)`, `warmUp(WarmUpSpec)`; DEBUG only: `selfKillForTesting(afterMilliseconds:)`. `WorkerReply`: `pong(pid:, osBuild:)`, `capabilities(WorkerCapabilities)`, `planned(ExecutionPlan)`, `staged(StagedOutput)`, `verified`, `failed(JobError)`, `text(RecognizedText)`, `accepted`. `WorkerEvent`: `progress(JobID, Double)`, `spawned(JobID, Int32)`. `WorkerCapabilities` carries each hosted engine's id and the pairs it handles with their availability, so `RemoteEngine.handles`/`availability` answer locally |
| Acceptance | JSON round trip of every case (`@Test(arguments:)` over a fixture list) equals the original; a decoded envelope with another `protocolVersion` → `WorkerProtocolError.versionMismatch(expected:, found:)`, which the client maps to `JobError.engineDamaged(.worker)` (02 §7.5) |
| Effort | S |

**Files:** `Package.swift` (target `ZivletIPC`, test target `ZivletIPCTests`), create
`Sources/ZivletIPC/Envelope.swift`, `WorkerRequest.swift`, `WorkerReply.swift`, `WorkerEvent.swift`,
`WorkerCapabilities.swift`; `Sources/ZivletCore/Jobs/JobIdentity.swift` (`EngineID` is a closed enum `media, image`: add `worker` for damage reports and, in D2, `vision`);
`Tests/ZivletIPCTests/IPCRoundTripTests.swift`; `Scripts/coverage.sh` (`GATED_MODULES`).

```swift
@Test(arguments: IPCFixtures.requests)
func everyRequestSurvivesTheWire(_ request: WorkerRequest) throws {
    let data = try JSONEncoder().encode(Envelope(request))
    #expect(try Envelope<WorkerRequest>.decode(data).body == request)
}

@Test func anotherProtocolVersionIsRefused() throws {
    let data = try JSONEncoder().encode(Envelope(protocolVersion: WorkerProtocol.version + 1, body: WorkerRequest.ping))
    #expect(throws: WorkerProtocolError.versionMismatch(expected: WorkerProtocol.version, found: WorkerProtocol.version + 1)) {
        try Envelope<WorkerRequest>.decode(data)
    }
}
```

RED: `no such module 'ZivletIPC'`. Commit `feat(ipc): the worker's requests, replies and events with a protocol
version`.

---

## Task C2 — Validation at the worker's boundary

| Field | Value |
|---|---|
| Goal | `WorkerRequestValidator.validate(_:) throws(JobError)` runs in the worker on every request before any engine sees it (03b, D-M6-4): every URL is a `file:` URL with an absolute, standardised path, no `..` component, no NUL; an input exists and is a regular file (`lstat`, not following a symlink at the last component); a staged file's parent is an existing directory and its name has the staging prefix the `Publisher` uses; a plan's engine id is one the worker hosts; `outputByteLimit` is nil or > 0; text jobs (D8) carry 1…500 inputs and a page cap. Failures map to the existing taxonomy (`.unsupportedInput(.notAFile)`, `.invalidDestination`, `.internalInvariant`) |
| Acceptance | table of good and bad requests: relative path, `..`, a symlink to `/etc/hosts` as input, a directory as input, a staged file outside a folder, a staged name without the prefix, an unknown engine, a zero byte limit — each refused with its case; the good ones pass |
| Effort | S |

**Files:** create `Sources/ZivletIPC/WorkerRequestValidator.swift`, `Tests/ZivletIPCTests/ValidatorTests.swift`.

RED: `cannot find 'WorkerRequestValidator' in scope`. Commit `feat(ipc): validate every worker request at the
boundary`.

---

## Task C3 — `WorkerService`: the worker's logic without XPC

| Field | Value |
|---|---|
| Goal | `actor WorkerService(engines: [any Engine], clock:, idleAfter: .seconds(60), onIdle:)`. `handle(_ request:, events: @Sendable (WorkerEvent) -> Void) async -> WorkerReply`: validates (C2); `prepare`/`verify` call the engine; `execute` runs the engine in a child `Task` stored by `JobID` and forwards the engine's `ProgressSink` and `spawned` as events; `cancel(id)` cancels that task (a cancel for an unknown id is a no-op reply `accepted`); every engine error comes back as `.failed(JobError)`. The idle timer starts when the last running job ends and fires `onIdle` after `idleAfter` unless a request arrives (D-M6-10) |
| Acceptance | fake engines from `EngineTestSupport`: `prepare` → `planned` with the fake plan; `execute` → `staged` and progress events in order; cancel while a fake execute waits → `.failed(.cancelled)` within 100 ms (manual clock for the fake's wait); two jobs in parallel are independent; an unknown engine → `.failed(.engineMissing)`; idle fires once 60 s after the last job with a manual clock, and not while a job runs |
| Effort | M |

**Files:** `Package.swift` (targets `ZivletWorkerCore`, `ZivletWorkerCoreTests`), create
`Sources/ZivletWorkerCore/WorkerService.swift`, `JobRegistry.swift`, `IdleTimer.swift`;
`Tests/ZivletWorkerCoreTests/WorkerServiceTests.swift`, `IdleTimerTests.swift`.

```swift
@Test func cancelStopsARunningExecuteQuickly() async throws {
    let engine = FakeEngine(execute: .waitUntilCancelled)
    let service = WorkerService(engines: [engine], clock: ManualClock(), idleAfter: .seconds(60), onIdle: {})
    let job = JobID()
    async let reply = service.handle(.execute(job, try FakePlans.png(job), outputByteLimit: nil), events: { _ in })
    try await engine.reachedExecute()
    let started = ContinuousClock.now
    _ = await service.handle(.cancel(job), events: { _ in })
    #expect(await reply == .failed(.cancelled))
    #expect(ContinuousClock.now - started < .milliseconds(100))
}
```

RED: `no such module 'ZivletWorkerCore'`. Commit `feat(worker): a transport-free worker service with cancel and
idle exit`.

---

## Task C4 — `WorkerConnection`: sessions, in-flight calls, crash detection

| Field | Value |
|---|---|
| Goal | In `ZivletRuntime`: `protocol WorkerTransport: Sendable` (`open(onEvent:, onClosed:) throws -> any WorkerChannel`; a channel has `send(_ request:) async throws(JobError) -> WorkerReply` and `close()`), `LoopbackTransport` (JSON-encodes, calls a `WorkerService`, decodes; can be told to "crash" on the n-th call or when a job id is seen, which closes the channel with `.interrupted`), and `actor WorkerConnection(transport:)`. The connection opens a channel lazily, keeps a table of in-flight calls, and when the channel closes (D-M6-2: an interruption cancels the session) fails every in-flight call with `.workerCrashed` and drops the channel; the next call opens a new one. A channel closed while nothing is in flight (the worker's idle exit) fails nothing. Events are routed to the call's progress sink by `JobID` |
| Acceptance | loopback: ping works; a crash during one of three in-flight executes fails all three with `.workerCrashed`, and the next ping opens a new channel (open count 2); an idle close fails nothing and the next call reopens; events for an unknown job are dropped and logged; `JobError` gains `.workerCrashed` and `.engineCrashedOnInput` (Codable, with copy in `JobErrorCopy`: "The converter stopped unexpectedly." and "This file made the engine crash.") |
| Effort | M |

**Files:** create `Sources/ZivletRuntime/WorkerTransport.swift`, `WorkerConnection.swift`,
`LoopbackTransport.swift`; modify `Sources/ZivletCore/Jobs/JobError.swift`, `Sources/ZivletCore/Jobs/JobError+Log.swift`,
`Sources/ZivletRuntime/JobErrorCopy.swift`; tests `Tests/ZivletRuntimeTests/WorkerConnectionTests.swift`, extend
the `JobErrorCopy` tests.

```swift
@Test func aCrashFailsEveryCallInFlightAndTheNextCallReopens() async throws {
    let transport = LoopbackTransport(service: .fake(executeWaits: true), crashOnCall: 3)
    let connection = WorkerConnection(transport: transport)
    async let a = connection.execute(try FakePlans.png(), job: JobID(), progress: .discard)
    async let b = connection.execute(try FakePlans.png(), job: JobID(), progress: .discard)
    async let c = connection.execute(try FakePlans.png(), job: JobID(), progress: .discard)
    let results = await [a, b, c].map { $0 }
    #expect(results.allSatisfy { $0 == .failure(.workerCrashed) })
    #expect(try await connection.ping().pid > 0 && transport.openCount == 2)
}
```

RED: `cannot find 'LoopbackTransport' in scope`. Commit `feat(runtime): a worker connection that notices a crash
and reopens`.

---

## Task C5 — `RemoteEngine`: an `Engine` that runs in the worker

| Field | Value |
|---|---|
| Goal | `struct RemoteEngine: Engine` built from one `WorkerCapabilities` engine entry and a `WorkerConnection`. `handles`/`availability` answer from the capabilities (fetched once per session, refreshed after a reopen). `prepare`, `execute`, `verify` send the matching request; `execute` installs a progress route for the job and forwards `spawned` to `ExecutionContext.spawned` (unused by EngineImage, ready for EngineMedia, G-M6-1); a cancelled Swift task sends `.cancel(job)` (`withTaskCancellationHandler`) and returns `.cancelled` when the worker replies |
| Acceptance | parity suite: the same PNG → JPEG, HEIC → PNG and SVG → PDF jobs through `RemoteEngine` over loopback and through `ImageEngine` in-process give byte-identical staged files and equal plans and notes; progress reaches the sink in order and before `execute` returns (the pipeline's ordering rule); cancelling the job task during a slow fake execute → `.cancelled` and the worker's task is cancelled |
| Effort | M |

**Files:** create `Sources/ZivletRuntime/RemoteEngine.swift`; tests `Tests/ZivletRuntimeTests/RemoteEngineTests.swift`
(real `ImageEngine` inside a loopback `WorkerService`; fixtures from `EngineTestSupport`).

RED: `cannot find 'RemoteEngine' in scope`. Commit `feat(runtime): run image engines through the worker connection`.

---

## Task C6 — One serial retry after a crash, then "This file made the engine crash"

| Field | Value |
|---|---|
| Goal | In `JobPipeline`: a step that fails with `.workerCrashed` discards the staging, waits for the `retry` gate (a new `LaneGates.retry`, width 1, so retries run one at a time — 05's "singly"), claims new staging and runs the whole job again once. A second `.workerCrashed` for the same job becomes `.engineCrashedOnInput` and the job fails; other jobs of the batch continue. While retrying, the job reports `.preparing` with a retry flag so the HUD's working line can say "Trying again…" |
| Acceptance | crashing loopback: (a) a crash on one of 5 jobs → that job retried once and succeeds, the other 4 succeed, never two retries at once; (b) a job whose input id always crashes → `.failed(.engineCrashedOnInput)` after exactly two attempts, and the next job of the batch succeeds; (c) staging is empty after each failed attempt; (d) the existing 200-file batch test and cancellation tests stay green |
| Effort | S |

**Files:** modify `Sources/ZivletRuntime/JobPipeline.swift`, `Sources/ZivletRuntime/LaneWidths.swift` (retry gate),
`Sources/ZivletCore/Jobs/JobState.swift` (retry flag on `.preparing` if needed); tests
`Tests/ZivletRuntimeTests/WorkerRetryTests.swift`.

```swift
@Test func aFileThatCrashesTwiceFailsAloneAndTheBatchGoesOn() async throws {
    let rig = try SchedulerRig(worker: .loopback(crashWhenInputIs: "bad.png"), files: ["a.png", "bad.png", "c.png"])
    let states = try await rig.runBatch()
    #expect(states["bad.png"] == .failed(.engineCrashedOnInput))
    #expect(states["a.png"]?.isSucceeded == true && states["c.png"]?.isSucceeded == true)
    #expect(rig.transport.attempts(for: "bad.png") == 2)
}
```

RED: `bad.png` ends `.failed(.workerCrashed)` after one attempt. Commit `feat(runtime): retry a job once after a
worker crash, then name the file`.

---

## Task C7 — Choosing the worker or the in-process fallback

| Field | Value |
|---|---|
| Goal | `WorkerSelection.engines(bundle:, integrity:, connect:) async -> EngineSet` (D-M6-9): if `Contents/XPCServices/ZivletWorker.xpc` exists **and** passes `SignedHelperCheck` (the existing helper policy: inside the bundle, valid signature, same team when the app has one) **and** a ping answers within 30 s → `RemoteEngine`s for EngineImage; otherwise the in-process `ImageEngine` and one log line with the reason. EngineMedia is in-process either way (D-M6-5). The choice is made once per launch, lazily at the first job (never at launch). Vision is never chosen in-process (D-M6-8): `EngineSet.textRecognition` is nil without a worker |
| Acceptance | fakes: missing bundle → in-process, reason "worker missing"; failed signature → in-process, reason "worker damaged", and the HUD copy for a later crash is unaffected; ping timeout (manual clock) → in-process; all good → remote; `textRecognition` nil in every fallback |
| Effort | S |

**Files:** create `Sources/ZivletRuntime/WorkerSelection.swift`; tests `Tests/ZivletRuntimeTests/WorkerSelectionTests.swift`.

RED: `cannot find 'WorkerSelection' in scope`. Commit `feat(runtime): use the worker when it is there and sound,
else run in-process`.

---

## Task C8 — Peer requirements on both sides

| Field | Value |
|---|---|
| Goal | `WorkerPeerPolicy.requirement(own: SigningIdentity) -> PeerRequirementSpec` (pure, D-M6-7): with a valid Team ID → `.sameTeam(identifier: peerIdentifier)`; ad-hoc → `.signingIdentifier(peerIdentifier)`. `SigningIdentity` is read from the running code with `SecCodeCopySelf` + `SecCodeCopySigningInformation` (team id, identifier), reusing `HelperIntegrity.Policy.validTeamID`. The app requires the worker's identifier `app.zivlet.Zivlet.Worker`; the worker requires the app's `app.zivlet.Zivlet`. The two XPC files map the spec to `XPCPeerRequirement.isFromSameTeam(andMatchesSigningIdentifier:)` or `XPCPeerRequirement(lightweightCodeRequirements:)` with `signing-identifier` (prototype §3.1) |
| Acceptance | pure tests for the mapping (team, ad-hoc, malformed team id → ad-hoc path with a logged warning); Z5 shows the ad-hoc path working in Debug; OS-M6-1 covers the team path |
| Effort | S |

**Files:** create `Sources/ZivletIPC/WorkerPeerPolicy.swift`, `Sources/ZivletRuntime/SigningIdentity.swift`; tests
`Tests/ZivletIPCTests/PeerPolicyTests.swift`.

RED: `cannot find 'WorkerPeerPolicy' in scope`. Commit `feat(ipc): require the peer's team, or its signing
identifier when ad-hoc`.

---

## Task C9 — The worker target

| Field | Value |
|---|---|
| Goal | `Worker/main.swift` and `Worker/Info.plist` (`CFBundleIdentifier app.zivlet.Zivlet.Worker`, `CFBundlePackageType XPC!`, `XPCService.ServiceType Application`, `LSMinimumSystemVersion 26.0`). `main.swift` (< 120 lines): builds the engines and a `WorkerService` with `onIdle: { exit(0) }`, starts `XPCListener(service:requirement:)` with a `XPCPeerHandler` per session that decodes `Envelope<WorkerRequest>`, replies through `handoffReply` for long steps, and sends `WorkerEvent`s through the session; calls `setlocale(LC_CTYPE, "UTF-8")` (05 §9.1 P2-19 note). `#if DEBUG` handles `selfKillForTesting` with `kill(getpid(), SIGKILL)` (D-M6-18). `project.yml`: target `ZivletWorker`, `type: xpc-service`, sources `[Worker]`, dependency on the package products `ZivletWorkerCore`, `ZivletIPC`, `EngineImage`, settings `PRODUCT_BUNDLE_IDENTIFIER app.zivlet.Zivlet.Worker`, `SWIFT_DEFAULT_ACTOR_ISOLATION nonisolated`, hardened runtime from `Base.xcconfig`, **no** entitlements file; the app target depends on it with `embed: true` (copied to `Contents/XPCServices`). `Package.swift` exports the two new libraries in the `ZivletKit` product |
| Acceptance | `make app` builds a Debug app whose `Contents/XPCServices/ZivletWorker.xpc/Contents/MacOS/ZivletWorker` exists, `codesign -dv` shows `runtime`, `codesign -d --entitlements -` is empty; `make release-check` passes and its scan finds no `selfKillForTesting` marker in Release (add the marker to `check-release-paths.sh` first: RED is the scan failing on a Debug-flag string planted in a test binary, as for the existing flags) |
| Effort | M |

**Files:** create `Worker/main.swift`, `Worker/Info.plist`; modify `project.yml`, `Packages/ZivletKit/Package.swift`,
`Scripts/check-release-paths.sh`, `Scripts/tests/test-release-flags.sh`.

RED: `Scripts/tests/test-release-flags.sh` with the new marker planted fails to report it. Commit
`feat(worker): the ZivletWorker XPC service, embedded and signed with the hardened runtime`.

---

## Task C10 — Signing and bundle checks know the worker

| Field | Value |
|---|---|
| Goal | `sign-app.sh` signs `Contents/XPCServices/*.xpc` inside-out after libraries, helpers and frameworks and before the app (`--options runtime`, `--identifier app.zivlet.Zivlet.Worker`, no entitlements; ad-hoc needs no library-validation exception because the worker loads only system libraries — check with `otool -L` in the test). `check-bundle.sh` requires the worker, checks its dependencies like a helper's (only `/usr/lib`, `/System`, or the app's `Frameworks`), and that its `Info.plist` identifier is right. `verify-signatures.sh` needs no change (it scans every Mach-O), but its script test gains a bundle with an unsigned worker that must fail |
| Acceptance | script tests: a fake bundle without the worker fails `check-bundle.sh`; a worker loading `/opt/homebrew/...` fails; an unsigned worker fails `verify-signatures.sh`; `sign-app.sh -` on a fake bundle signs the worker before the app (`codesign --verify --strict --deep` passes); the real `make release-check` passes |
| Effort | S |

**Files:** modify `Scripts/sign-app.sh`, `Scripts/check-bundle.sh`; tests `Scripts/tests/test-check-bundle.sh`,
`Scripts/tests/test-signatures.sh`.

RED: the "bundle without the worker" case passes `check-bundle.sh` today. Commit `chore(scripts): sign and check the
worker in the bundle`.

---

## Task C11 — App wiring

| Field | Value |
|---|---|
| Goal | `App/ConversionWiring.swift` builds the scheduler's engines through `WorkerSelection` (C7) with `XPCSessionFactory` as the transport (`Packages/.../ZivletRuntime/XPCSessionFactory.swift`, the second XPC file); quitting cancels the session after the scheduler's quit wait (≤ 2 s, P1-31). The status menu's Diagnostics include "Worker: running (pid n) / in-process (reason)" without paths |
| Acceptance | `make app`; `make convert-demo FILE=<temp png> TO=jpg` succeeds and the log shows the worker's pid ≠ the app's pid; with the worker removed from a copied Debug bundle the same demo succeeds in-process and logs the reason; `make test` green |
| Effort | S |

**Files:** create `Packages/ZivletKit/Sources/ZivletRuntime/XPCSessionFactory.swift`; modify
`App/ConversionWiring.swift`, `Packages/ZivletKit/Sources/ZivletRuntime/Diagnostics.swift`; test the diagnostics line
in `Tests/ZivletRuntimeTests/DiagnosticsTests.swift`.

RED: the diagnostics test expects a worker line that does not exist. Commit `feat(app): run image conversions in the
worker`.

---

## Task C12 — Worker smoke (exit row Z5)

| Field | Value |
|---|---|
| Goal | A DEBUG launch flag `-ZivletWorkerSmoke <folder>` (scanned by `check-release-paths.sh` like the other DEBUG flags) makes the app, without UI, run in order: PNG → JPEG of a fixture it writes into `<folder>`; a slow fake-sized job cancelled after 200 ms (cancel visible ≤ 100 ms); a job during which it sends `selfKillForTesting(0)` once (retried, succeeds); a job that self-kills on both attempts ("This file made the engine crash", the next job succeeds); then it waits for the idle exit (flag `-ZivletWorkerIdleSeconds 5`) and checks the worker pid is gone. It writes one JSON line per step to `<folder>/worker-smoke.jsonl` and quits. `Scripts/worker-smoke.sh` (and `make worker-smoke`) runs it on a temporary folder it creates, prints pass/fail per step with the relaunch times (R2), checks that no `ZivletWorker-*.ips` crash report appeared during the run, and deletes only that folder |
| Acceptance | `make worker-smoke` passes on the Debug build; its shell test runs the script against a fake app binary that writes canned lines (pass and fail) |
| Effort | M |

**Files:** create `App/WorkerSmoke.swift`, `Scripts/worker-smoke.sh`, `Scripts/tests/test-worker-smoke.sh`; modify
`App/AppDelegate+Demo.swift`, `Makefile` (`worker-smoke`), `Scripts/check-release-paths.sh`.

RED: `Scripts/tests/test-worker-smoke.sh` fails (no script). Commit `test(worker): a smoke run of the real worker:
cancel, crash, retry, idle exit`.

---

## Stream C checks before Stream D's wiring

`nice -n 10 make test lint coverage app release-check`; `make worker-smoke`; `Scripts/m5a-exit.sh --only X2` (the
HUD timing row, since job events now cross a process); record the PNG → JPEG time in-process vs worker on the bench
corpus (`make bench`, for E4's record).
