# 10h — M4 stream F: CI, Sparkle, DMG, notarization, appcast, release workflow, M4 exit

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. Everything here is built up
to the step that needs the owner; each owner step is a named input (secret, file or decision) and every script fails
with a message naming the owner step (O-n, index §7) when that input is missing. Nothing here pushes, tags or
publishes; the Verify phase does that.

---

## Task F1 — CI workflows on a self-hosted runner: `ci.yml`, `nightly.yml`, `vendor.yml` (P0-07, P0-37)

| Field | Value |
|---|---|
| Goal | Hosted GitHub macOS images do not have Xcode 27 / Swift 6.4 (05 P0-07 note), so every job uses `runs-on: [self-hosted, macOS, ARM64, zivlet]`. **ci.yml** (pull_request, push to `main`): `make vendor-test`, `Vendor/unpack.sh` from the cache or `make vendor`, `make lint test coverage app`, `make release-check`, `ZIVLET_MATRIX=subset make matrix`, `make licence-gate`; uploads test and coverage reports. **nightly.yml** (cron 03:00 UTC + manual): `ZIVLET_MATRIX=full make matrix` (161 pairs + hostile corpus), `make bench` with the compare gate, `Vendor/repro-check.sh`, the 20× wheel-test loop (E7). **vendor.yml** (paths `Vendor/**`): `make vendor`, `Vendor/pack.sh`, uploads `zivlet-vendor-<key>.tar.xz` and the source bundle as artifacts (cache key A7). All jobs: `permissions: contents: read`, `concurrency` per ref, `DEVELOPER_DIR` set, no secrets |
| 05 rows | P0-07, P0-37 (hosted half), P1-61 (nightly), P1-63 (nightly) |
| Owner | O-4: register the runner (label `zivlet`) on the owner's Mac or the Tart host. Until then the workflows exist but do not run; the same commands run locally with `make ci-local` |

**Files:** create `.github/workflows/ci.yml`, `.github/workflows/nightly.yml`, `.github/workflows/vendor.yml`,
`Scripts/tests/test-workflows.sh`; modify `Makefile` (`ci-local` runs the ci.yml steps in order).

### F1.1 Failing test first

`Scripts/tests/test-workflows.sh` parses the YAML with the system Ruby (`/usr/bin/ruby -ryaml`; checked present on
macOS 27.0; Python has no YAML module here) and asserts: every job's `runs-on` contains `self-hosted` and `zivlet`;
no workflow uses `pull_request_target`; `ci.yml`, `nightly.yml` and `vendor.yml` grant only `contents: read`; every
`uses:` is pinned to a 40-hex commit SHA; `ci.yml` runs `make lint`, `make test`, `make coverage`,
`make release-check`; `nightly.yml` sets `ZIVLET_MATRIX: full`.

### F1.2–F1.5

RED: workflows missing. GREEN: `bash Scripts/tests/test-workflows.sh`; `make ci-local` exits 0 on the dev Mac. Commit
`ci: pull-request, nightly and vendor workflows for a self-hosted runner`.

---

## Task F2 — Sparkle 2 integration with a placeholder feed (P1-53 part, D-M4-11)

| Field | Value |
|---|---|
| Goal | SwiftPM dependency `https://github.com/sparkle-project/Sparkle` exact `2.10.0` on the app target (added in `project.yml` `packages:`). `UpdaterService` (in `ZivletUI`) wraps `SPUStandardUpdaterController`; `UpdaterConfiguration.validate(feedURL:publicKey:)` decides: feed must be `https://`, host not ending in `.invalid` for a real feed; public key must be 44 base64 characters (32-byte Ed25519). With the placeholder feed `https://updates.zivlet.invalid/stable/appcast.xml` or an empty key, the updater is **not started**, "Check for Updates…" is disabled and Settings › Updates says "Updates aren't set up in this build yet." (*new*). `Info.plist`: `SUFeedURL = $(ZIVLET_FEED_URL)`, `SUPublicEDKey = $(SPARKLE_PUBLIC_ED_KEY)`, `SUEnableAutomaticChecks` from settings, `SUAutomaticallyUpdate` NO, `SUVerifyUpdateBeforeExtraction` YES. `Config/Release.xcconfig` and `Debug.xcconfig` define both variables (placeholder / empty). Zivlet is not sandboxed, so Sparkle's XPC services are not needed; strip `Sparkle.framework/Versions/B/XPCServices` in the embed phase and thin the framework to arm64 (`lipo -thin arm64`), measured in A14 |
| 05 rows | P1-53 (Sparkle stable channel up to the key) |
| Sources | 10 §11.4, 14 §3.5, Sparkle 2 documentation (sandboxing section) |
| Owner | O-2 (EdDSA key pair: private key offline + CI secret; public key into `Release.xcconfig`), O-3 (final feed URL / domain / bundle id) |

**Files:** create `Sources/ZivletUI/Updates/UpdaterConfiguration.swift`, `UpdaterService.swift`,
`Tests/ZivletUITests/UpdaterConfigurationTests.swift`; modify `project.yml`, `Config/*.xcconfig`, `App/AppDelegate.swift`,
`Scripts/embed-helpers.sh` (Sparkle trim), `THIRD_PARTY_NOTICES.md` (Sparkle MIT → Present).

### F2.1 Failing test first

```swift
@Suite("Updater configuration (F2)")
struct UpdaterConfigurationTests {
    static let key = String(repeating: "A", count: 43) + "="

    @Test func placeholderFeedDisablesUpdates() {
        let config = UpdaterConfiguration.validate(feedURL: "https://updates.zivlet.invalid/stable/appcast.xml",
            publicKey: Self.key)
        #expect(config == .disabled(.placeholderFeed))
    }

    @Test func missingKeyDisablesUpdates() {
        #expect(UpdaterConfiguration.validate(feedURL: "https://example.org/appcast.xml", publicKey: "")
            == .disabled(.missingKey))
    }

    @Test func plainHTTPIsRefused() {
        #expect(UpdaterConfiguration.validate(feedURL: "http://example.org/appcast.xml", publicKey: Self.key)
            == .disabled(.insecureFeed))
    }

    @Test func aRealFeedAndKeyEnableUpdates() {
        #expect(UpdaterConfiguration.validate(feedURL: "https://example.org/appcast.xml", publicKey: Self.key)
            == .enabled)
    }

    @Test(arguments: ["short", String(repeating: "A", count: 44) + "!", String(repeating: "#", count: 44)])
    func malformedKeysAreRefused(key: String) {
        #expect(UpdaterConfiguration.validate(feedURL: "https://example.org/a.xml", publicKey: key)
            == .disabled(.malformedKey))
    }
}
```

### F2.2–F2.5

RED: missing types. GREEN: `swift test --filter UpdaterConfigurationTests`; `make app` and `make release-check`
succeed with Sparkle linked; Settings › Updates shows the not-set-up sentence. Commit `feat(updates): Sparkle 2 with
a placeholder feed; disabled until the owner's key and feed exist`.

---

## Task F3 — DMG script (P1-53 part)

| Field | Value |
|---|---|
| Goal | `Scripts/make-dmg.sh <app> <version> [--identity <id>]` → `build/release/Zivlet-<version>.dmg`: a staging folder with `Zivlet.app` and an `Applications` symlink, `hdiutil create -fs APFS -format ULMO -volname "Zivlet <version>"`, then `codesign --timestamp --sign <id>` on the DMG when an identity is given; `hdiutil verify`; prints size. No third-party DMG tool and no background artwork (our own simple layout; a designed background can come later as our own asset) |
| 05 rows | P1-53 |

**Files:** create `Scripts/make-dmg.sh`, `Scripts/tests/test-make-dmg.sh` (build a DMG from a tiny fake app; mount it
with `hdiutil attach -nobrowse -readonly` into a temp mount point; assert `Zivlet.app` and the `Applications` link
exist; detach; a missing app path fails with a message).

Commit `chore(release): DMG script`.

---

## Task F4 — Notarization and stapling script (P1-53 part)

| Field | Value |
|---|---|
| Goal | `Scripts/notarize.sh <file.zip|file.dmg>`: requires `ZIVLET_NOTARY_PROFILE` (a `notarytool store-credentials` keychain profile on the release runner) — or `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_PATH` for an App Store Connect API key; runs `xcrun notarytool submit --wait --output-format json`, fails on any status but `Accepted` and prints the log URL via `notarytool log`; staples (`xcrun stapler staple`) and validates (`stapler validate`); for an app, `spctl -a -vv -t exec` must say `source=Notarized Developer ID`. Without credentials: exit 3 with "Notarization needs the owner's Developer ID and notary key (owner step O-1)." |
| 05 rows | P1-53 |
| Owner | O-1 |

**Files:** create `Scripts/notarize.sh`, `Scripts/tests/test-notarize.sh` (no credentials → exit 3 and the O-1
sentence; a fake `xcrun` on `PATH` returning `Invalid` JSON → exit 1 and the log step is called).

Commit `chore(release): notarize and staple script`.

---

## Task F5 — Appcast, SBOM and release notes (P1-53 part)

| Field | Value |
|---|---|
| Goal | `Scripts/make-appcast.sh <dir-with-dmgs>` uses Sparkle's `generate_appcast` from `Vendor/out/sparkle-tools/bin` (extracted from the pinned Sparkle tarball, A1) with `--ed-key-file -` reading the private key from the `SPARKLE_ED_PRIVATE_KEY` environment variable (or `--account` keychain item on the runner), `--download-url-prefix` from `ZIVLET_DOWNLOAD_URL_PREFIX`, release notes from `docs/release-notes/<version>.md` converted to HTML, deltas against the previous two DMGs present in the directory, channel `stable`. Without the key: exit 3 "Signing the appcast needs the owner's Sparkle key (owner step O-2)." `Scripts/sbom.sh <version>` writes SPDX 2.3 JSON (`build/release/zivlet-<version>.spdx.json`) from `Vendor/licenses.json`, the resvg crate tree (`cargo metadata`), and Zivlet itself |
| 05 rows | P1-53 |
| Owner | O-2, O-3 |

**Files:** create `Scripts/make-appcast.sh`, `Scripts/sbom.sh`, `docs/release-notes/0.1.0-alpha.md` (draft, our own
words), `Scripts/tests/test-appcast.sh` (no key → exit 3; with a throwaway key generated by `generate_keys` into a
temp keychain-free file and two fake DMGs, the appcast validates as XML, has two items with `sparkle:edSignature`),
`Scripts/tests/test-sbom.sh` (JSON parses; every lock entry is a package; licence ids match the manifest).

Commit `chore(release): appcast, SBOM and release-notes scripts`.

---

## Task F6 — `release.yml` (P1-53)

| Field | Value |
|---|---|
| Goal | Trigger: tag `v*` and `workflow_dispatch` (input `dry_run`, default true). `runs-on: [self-hosted, macOS, ARM64, zivlet-release]`, `environment: release` (protected: owner approval, secrets scoped to it). Steps: checkout at the tag → `Vendor/unpack.sh` (or build) → `make licence-gate` → xcodegen → `xcodebuild archive` Release → export app → `sign-app.sh "$DEVELOPER_ID"` → `verify-signatures.sh --require-developer-id` → zip + `notarize.sh` → staple app → `make-dmg.sh --identity` → `notarize.sh` DMG → `size-gate.sh app dmg` → `source-bundle.sh` → `sbom.sh` → dSYMs zip (app + helper dSYMs from A4) → `make-appcast.sh` → `Scripts/vm-smoke.sh` (Tart VM with macOS 26.0: copy the DMG in, mount, `spctl` the app, launch it with `-ZivletDemoConvert` for one media and one image pair, expect `1 saved`) → `gh release create --draft` with DMG, source bundle, SBOM, dSYMs, appcast. `dry_run: true` or any missing secret → the same steps with the ad-hoc identity, notarization and appcast signing skipped with the owner-step messages, assets uploaded as workflow artifacts only (no release) |
| 05 rows | P1-53 |
| Owner | O-1 (Developer ID + notary), O-2 (Sparkle key), O-3 (feed URL, download prefix, bundle id), O-4 (release runner + Tart images) |

**Files:** create `.github/workflows/release.yml`, `Scripts/vm-smoke.sh`, `Scripts/release-local.sh` (same steps,
for `make release-dry-run`); extend `Scripts/tests/test-workflows.sh` (release job uses `environment: release`, only
`contents: write` permission, all actions pinned by SHA, `dry_run` default true, secrets referenced only in steps that
need them).

Commit `ci: release workflow up to the owner's signing, notarization and appcast keys`.

---

## Task F7 — Local release dry run (P0-38 dry-run half)

`make release-dry-run` runs `Scripts/release-local.sh 0.1.0-dryrun` on the dev Mac: Release build with bundled
helpers, ad-hoc signing, `verify-signatures.sh` (report-only), DMG, size gate, licence gate, source bundle, SBOM,
unsigned appcast. Expected output (projection, A14): app ≈ 38–40 MB installed, DMG ≈ 16–18 MB, `Licences OK`, `size
OK`. The DMG is then mounted and the app launched from it with `-ZivletDemoConvert` for `jpg → webp`, `svg → png`,
`m4a → ogg` and `mov → webm`: each `1 saved`. This proves everything except Developer ID, notarization, Gatekeeper on a
clean VM, and the Sparkle N-1 → N update, which need O-1…O-4. No commit (verification task); record numbers in the M4
record.

---

## Task F8 — M4 exit check and alpha (P1-65)

### Automated (agent, `Scripts/m4-exit.sh`, `make m4-exit`; results in [11 §4](11-m4-record.md))

| # | Check | Expected |
|---|---|---|
| X1 | `make vendor-test lint test coverage app release-check licence-gate` | all exit 0; coverage ≥ 80 % for every gated module (now 13: + ZivletActions, ZivletSettings, ZivletUI; `zivlet-fixtures` not gated) |
| X2 | `ZIVLET_FFMPEG_DIR=Vendor/out/media-stage/Helpers make smoke` | 16 cases, 0 known issues (B5 adds the untagged-HDR case) |
| X3 | `ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke` (owner gate list) | passes; Homebrew lacks libvorbis and zscale, so those cases stay known issues there (D-M3-6) |
| X4 | `ZIVLET_MATRIX=full make matrix` | 161 pairs pass with the vendored build; hostile corpus: every file refused or contained, no canary bytes |
| X5 | `make fixtures-check`, `Vendor/repro-check.sh` | deterministic fixtures; repro differences none or listed with evidence |
| X6 | `make bench` | HEIC→JPEG and 1-min MOV→MP4 within budget on this Mac (tagged 27-only, M2 Pro); idle wake-ups 0 |
| X7 | `make release-dry-run` | F7 numbers; size gate OK |
| X8 | Demo set (05 P1-33, incl. the M3-deferred `png → webp`) through the Release app from the dry-run DMG | jpg→png, png→webp, heic→jpg, mov→mp4, wav→mp3, mp4→webm: each `1 saved`, verified, revealed |
| X9 | No TCC prompt other than folder prompts | DEBUG app launched, all demos run, `tccutil`-free log shows no Accessibility/Input Monitoring request (`log show --predicate 'subsystem == "com.apple.TCC"'`) |

### Owner (index §7)

O-1 … O-6 as listed in the index; M4 is complete when X1–X9 pass **and** O-1 (notarized DMG), O-2/O-3 (Sparkle stable
channel, N-1 → N update verified on a clean VM), O-4 (Tart smoke on 26.0), O-5 (tester list, `v0.1.0-alpha` tag) and
O-6 (real-drag matrix P1-64, onboarding usability P1-47, AirDrop/terminals/Move/launch-at-login checks, 120 Hz tap →
wheel p95 ≤ 16 ms) are done. Until then the M4 record says "code complete; owner steps outstanding", as M3 did.

Commit (agent part): `docs: M4 record` (written after execution, like 09).
