# QA checklist: the worker

Owner rows for the ZivletWorker XPC service (P2-01) from [18](../18-implementation-plan-m6.md) §7 and
[18c](../18c-m6-worker.md). The request validation, the transport-free service, the crash retry and the in-process
fallback are covered by unit tests; the real worker by `make worker-smoke` (Z5); its place, signature and empty
entitlements in the Release bundle by `make release-check` (Z4). These rows check what a person or a Developer ID
build adds.

## Setup

- A Debug build (`make app`) for WK1 and WK3–WK5; a Developer ID Release for WK2.
- At the top of the run, record the macOS build, the Mac model and the Zivlet commit.
- Mark each row **pass**, **fail** (with what happened) or **n/a** (with why). No result is written until it is
  seen. A fail opens an issue.

## W. Worker

| # | Check | Steps | Expected | Result |
|---|---|---|---|---|
| WK1 | Smoke on Debug (Z5) | `make worker-smoke` | Every line passes: a job in a process that is not the app, cancel, a retry after one crash, the crash message after two, idle exit, no crash report | |
| WK2 | A Developer ID signature (OS-M6-1) | Build Release with the Developer ID; convert a PNG to JPEG; `codesign -dv` the app and `Contents/XPCServices/ZivletWorker.xpc`. The smoke mode exists only in Debug, so for the full smoke sign a Debug build with the Developer ID and run `Scripts/worker-smoke.sh <that app>` | The conversion runs in `ZivletWorker`; both show the same TeamIdentifier; the log has no "Malformed Team ID" line (the same-team requirement was used); the signed Debug smoke passes as WK1 | |
| WK3 | Seen in Activity Monitor | Convert a few PNGs to JPEG; watch Activity Monitor | `ZivletWorker` appears during the conversion and is gone about a minute after the last job | |
| WK4 | Quit during a conversion | Start a long batch of image conversions; quit Zivlet | No `ZivletWorker` left running; no staging file left beside the outputs | |
| WK5 | Hostile images | Convert a truncated HEIC and a PNG whose header claims a huge size | Each fails with a message; the rest of the batch and the app carry on | |
