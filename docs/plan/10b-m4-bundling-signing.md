# 10b — M4 stream A, part 2: binary targets, bundling, helper integrity, signing, licences, size

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. Depends on 10a (A1–A7).

---

## Task A9 — Binary targets in `Package.swift`; vendor outputs built on demand (D-M4-9)

| Field | Value |
|---|---|
| Goal | `EngineImage` links `CWebP` and `CZivletSVG` as `.binaryTarget(name:path:)` pointing at `../../Vendor/out/*.xcframework` (checked in the prototype: a SwiftPM 6.2 binary target may point outside the package directory). `make test`, `make coverage`, `make app` and `make release-check` first run `Vendor/ensure-native.sh`, which builds the two xcframeworks only when missing or stale (cache key, A7); about 25 s on a clean clone with tools present (4 s libwebp configure+build + 2 s package + 18 s Rust) |
| 05 rows | P1-25 (checksummed `binaryTarget`), P2-10 subset |
| Sources | 04 §3 ("Binary targets"), D-M4-9 |

**Files:** create `Vendor/ensure-native.sh`, `Vendor/tests/test-ensure-native.sh`; modify
`Packages/ZivletKit/Package.swift`, `Makefile`, `Scripts/coverage.sh` (no change to modules yet), `README.md`
(clean-clone prerequisites: `brew install cmake meson ninja autoconf automake libtool pkgconf rust`).

### A9.1 Failing test first

`Vendor/tests/test-ensure-native.sh`: with `ZIVLET_VENDOR_WORK` pointing at a temp copy of `Vendor/` minus `out/`,
`ensure-native.sh` builds both xcframeworks; a second run prints `CWebP up to date` and `CZivletSVG up to date` and
finishes in under 3 s; deleting `out/CWebP.xcframework/Info.plist` makes the next run rebuild only CWebP.

Swift side (`Tests/EngineImageTests/VendorLinkTests.swift`), proving the link works before any engine code uses it:

```swift
import CWebP
import CZivletSVG
import Testing

@Suite("Vendored libraries link and answer (A9)")
struct VendorLinkTests {
    @Test func libwebpIs160() {
        #expect(WebPGetEncoderVersion() == 0x01_06_00)
        #expect(WebPGetMuxVersion() == 0x01_06_00)
    }

    @Test func zivletSVGRefusesGarbage() {
        var image = ZivletSvgImage(width: 0, height: 0, rgba: nil)
        let bytes = Array("not svg".utf8)
        #expect(zivlet_svg_render(bytes, bytes.count, 2, 8192, &image) == ZIVLET_SVG_PARSE)
    }
}
```

### A9.2 Run, expect failure

`swift test --filter VendorLinkTests` → `error: no such module 'CWebP'`.

### A9.3 Implement

```swift
// Package.swift additions
.binaryTarget(name: "CWebP", path: "../../Vendor/out/CWebP.xcframework"),
.binaryTarget(name: "CZivletSVG", path: "../../Vendor/out/CZivletSVG.xcframework"),
.target(name: "EngineImage", dependencies: ["ZivletEngineKit", "CWebP", "CZivletSVG"], swiftSettings: strict),
```

Makefile: `NATIVE := Vendor/ensure-native.sh &&` prefixed to `test`, `smoke`, `coverage`, `app`, `release-check`.
`project.yml` needs nothing: the app gets the binaries through the `ZivletKit` product.

### A9.4 Verify green / A9.5 Commit

`make test` → previous 516 tests + 2. Commit `chore(vendor): link CWebP and CZivletSVG binary targets, built on
demand`.

---

## Task A10 — Bundle the media helpers into `Contents/Helpers` and `Contents/Frameworks` (P1-50)

| Field | Value |
|---|---|
| Goal | Every app build (Debug and Release) copies `Vendor/out/media-stage/Helpers/{ffmpeg,ffprobe}` to `Zivlet.app/Contents/Helpers/` and the seven dylibs to `Contents/Frameworks/`; licence texts to `Contents/Resources/Licenses/` (A13). Debug keeps `ZIVLET_FFMPEG_DIR`/Homebrew as fallbacks after the bundled helpers (D-M3-19, unchanged); Release finds the bundled ones |
| 05 rows | P1-50, P1-21 (now exercised for real), G-1 |
| Sources | 11 §7.1, 05 P1-50, D-M4-10 |

**Files:** create `Scripts/embed-helpers.sh`, `Scripts/check-bundle.sh`, `Scripts/tests/test-check-bundle.sh`;
modify `project.yml` (a post-build script phase on target `Zivlet`), `Makefile` (`release-check` and the F-stream
`dmg` target run `Vendor/ensure-media.sh` = unpack the cached stage or build it; `app` does not), and
`Scripts/check-release-paths.sh` (also runs `check-bundle.sh` on the Release app).

Why a script phase and not XcodeGen "Copy Files": the dylibs must keep their install names and be signed inside-out
by A12's script with the same identity as the app; a script phase that copies then calls `Scripts/sign-app.sh
--helpers-only` keeps one signing path for Xcode builds and the release pipeline (11 §7.2 says check copies made by
"Code Sign On Copy" and re-sign if needed; the script avoids the check-and-repair step). Record as D-M4-10.

### A10.1 Failing test first

`Scripts/tests/test-check-bundle.sh` builds a fake `.app` tree in a temp dir and asserts that `check-bundle.sh`:
fails when `Contents/Helpers/ffprobe` is missing; fails when `otool -L Contents/Helpers/ffmpeg` names a path that is
not `@rpath/`, `/usr/lib/` or `/System/Library/`; fails when a dylib named by `ffmpeg` is not present in
`Contents/Frameworks`; fails when `LC_RPATH` is not `@executable_path/../Frameworks`; passes on the real Debug app after
`make app`. The real-app branch runs `Contents/Helpers/ffmpeg -hide_banner -version` and expects `ffmpeg version 9.0.2`
— this proves the rpath resolves inside the bundle.

### A10.2 Run, expect failure

`bash Scripts/tests/test-check-bundle.sh` → `Scripts/check-bundle.sh: No such file or directory`.

### A10.3 Implement

`project.yml`:

```yaml
targets:
  Zivlet:
    postBuildScripts:
      - name: Embed media helpers
        script: "\"$SRCROOT/Scripts/embed-helpers.sh\""
        inputFiles: ["$(SRCROOT)/Vendor/out/media-stage/KEY"]
        outputFiles: ["$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/ffmpeg"]
        basedOnDependencyAnalysis: true
```

`embed-helpers.sh`: `ditto` Helpers and Frameworks from the stage, `ditto Vendor/out/licenses
Contents/Resources/Licenses`, then `Scripts/sign-app.sh --helpers-only "$CODE_SIGN_IDENTITY"` (ad-hoc `-` in Debug and
until the Developer ID exists). When the stage is absent: Release fails with "Media helpers are missing: run make
vendor"; Debug prints the same text as a build warning and continues, so a Debug app still works through
`ZIVLET_FFMPEG_DIR`/Homebrew (D-M3-19) on a machine that has not built the vendor tree.

### A10.4 Verify green

`make app && bash Scripts/tests/test-check-bundle.sh` → `PASS`. `make release-check` → `Release build contains no
Homebrew path.` and `Bundle OK: 2 helpers, 7 libraries`. App size after A10 is measured and written to the A14 size
report (expected ≈ 3.4 MB app + 29–30 MiB helpers).

### A10.5 Commit

`feat(app): bundle the vendored ffmpeg and ffprobe with their libraries`.

---

## Task A11 — Helper integrity check before first use (P1-50, 11 §7.4)

| Field | Value |
|---|---|
| Goal | Before the first spawn of a bundled helper in a launch, `HelperIntegrity.check(_:)` validates its code signature with `SecStaticCodeCheckValidity` (`kSecCSStrictValidate | kSecCSCheckAllArchitectures`) against a requirement derived from the running app: when the app has a Team ID, `anchor apple generic and certificate leaf[subject.OU] = "<team>"`; when the app is ad-hoc signed (Debug, or Release before the owner's Developer ID), no Team ID requirement but the signature must be valid and the helper must live inside `Bundle.main.bundleURL`. Helpers from `override`/`development` origins (Debug only) are not checked. Failure → new `JobError.engineDamaged(EngineID)` with the sentence "Zivlet's media engine is damaged. Reinstall Zivlet to fix it." and the media routes are reported unavailable (`["signature"]`) |
| 05 rows | P1-50 |
| Sources | 11 §7.4, 10 §8.9 |

**Files:** create `Sources/ZivletEngineKit/HelperIntegrity.swift`, `Tests/ZivletEngineKitTests/HelperIntegrityTests.swift`;
modify `Sources/ZivletCore/Jobs/JobError.swift` (+ `engineDamaged`, `logDescription`), `JobError+Log.swift`,
`Sources/ZivletRuntime/JobErrorCopy.swift`, `Sources/EngineMedia/MediaEngine.swift` (check once per tools directory,
result cached in an actor; concurrent first callers share one check like `SharedLoad`).

### A11.1 Failing tests first

```swift
import Foundation
import Testing
import ZivletCore

@testable import ZivletEngineKit

@Suite("Helper code-signature check (A11, 11 §7.4)")
struct HelperIntegrityTests {
    static func adHocSignedCopy(of tool: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: (tool as NSString).lastPathComponent)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: tool), to: url)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", url.path]
        try sign.run(); sign.waitUntilExit()
        #expect(sign.terminationStatus == 0)
        return url
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aValidAdHocSignatureInsideTheBundlePasses() throws {
        let dir = try Self.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        let policy = HelperIntegrity.Policy(teamID: nil, bundleRoot: dir)
        #expect(throws: Never.self) { try HelperIntegrity.check(tool, policy: policy) }
    }

    @Test func aModifiedBinaryFails() throws {
        let dir = try Self.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        let handle = try FileHandle(forUpdating: tool)
        try handle.seek(toOffset: 0x4000); try handle.write(contentsOf: Data([0xFF, 0xFF])); try handle.close()
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: nil, bundleRoot: dir))
        }
    }

    @Test func aHelperOutsideTheBundleFails() throws {
        let dir = try Self.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        let elsewhere = try Self.tempDir(); defer { try? FileManager.default.removeItem(at: elsewhere) }
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: nil, bundleRoot: elsewhere))
        }
    }

    @Test func aTeamRequirementRejectsAnAdHocHelper() throws {
        let dir = try Self.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: "ABCDE12345", bundleRoot: dir))
        }
    }

    @Test func theRequirementTextNamesTheTeam() {
        #expect(HelperIntegrity.Policy(teamID: "ABCDE12345", bundleRoot: URL(fileURLWithPath: "/")).requirement
            == #"anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#)
        #expect(HelperIntegrity.Policy(teamID: nil, bundleRoot: URL(fileURLWithPath: "/")).requirement == nil)
    }

    @Test func malformedTeamIDsAreRefused() {
        #expect(HelperIntegrity.Policy.validTeamID("ABCDE12345"))
        #expect(!HelperIntegrity.Policy.validTeamID("abc\"; or 1"))
        #expect(!HelperIntegrity.Policy.validTeamID(""))
    }
}
```

`MediaEngineTests` gains: a `FakeIntegrity` that throws makes `availability` return `.unavailable(["signature"])`
and `prepare` throw `engineDamaged(.media)`; eight concurrent `prepare` calls run the check once.

### A11.2 Run, expect failure

`swift test --filter HelperIntegrityTests` → `error: cannot find 'HelperIntegrity' in scope`.

### A11.3 Implement

`Policy.current()` reads the running app's signing information once (`SecCodeCopySelf` →
`SecCodeCopySigningInformation`, key `kSecCodeInfoTeamIdentifier`); a Team ID must match `^[A-Z0-9]{10}$` before it is
interpolated into the requirement string. `check` resolves symlinks of both paths and requires the helper's path to
have `bundleRoot`'s resolved path as a prefix. Errors from Security framework are logged with the `OSStatus`
(public) and the path (private).

### A11.4 Verify green / A11.5 Commit

`swift test --filter "HelperIntegrityTests|MediaEngineTests"` green; `make coverage` keeps EngineKit ≥ 80 %. Commit
`feat(engine): verify the bundled helpers' code signature before first use`.

---

## Task A12 — Signing scripts and signature gate (P0-38 dry-run half, P1-52)

| Field | Value |
|---|---|
| Goal | `Scripts/sign-app.sh [--helpers-only] <identity> <app>` signs inside-out (dylibs → helpers with `--identifier app.zivlet.helper.<name>` → frameworks such as Sparkle's nested items per Sparkle's docs → app with `Config/Zivlet.entitlements`), always `--options runtime`, plus `--timestamp` when the identity is not `-`. `Scripts/verify-signatures.sh <app> [--require-developer-id]` checks every Mach-O: `codesign --verify --strict`, `flags` contain `runtime`; with `--require-developer-id`: Team ID present and equal across all files, secure timestamp present, `spctl -a -vv -t exec` accepts (only after notarization). Without the flag (ad-hoc), it reports "report-only: ad-hoc signature" and exits 0 when the strict verify and runtime checks pass (05 §8 fallback) |
| 05 rows | P0-38 (scripts), P1-52 (signature gate) |
| Sources | 11 §7.2–7.3, 10 §11.2 |

**Files:** create `Scripts/sign-app.sh`, `Scripts/verify-signatures.sh`, `Scripts/tests/test-signatures.sh`.

### A12.1 Failing test first

`test-signatures.sh`: copy the Debug app to a temp dir; `sign-app.sh - <copy>`; `verify-signatures.sh <copy>` exits 0
and prints `report-only`; `codesign -dv` of `Contents/Helpers/ffmpeg` shows `flags=0x10002(adhoc,runtime)` and
`Identifier=app.zivlet.helper.ffmpeg`; appending one byte to `Contents/Frameworks/libavutil.61.dylib` makes
`verify-signatures.sh` exit 1 naming that file; `verify-signatures.sh <copy> --require-developer-id` exits 1 with
"Developer ID signature required (owner step O-1)".

### A12.2–A12.5

RED: scripts missing. GREEN: `bash Scripts/tests/test-signatures.sh` → `PASS`. Commit `chore(release): inside-out
signing and signature verification scripts`.

---

## Task A13 — Licence manifest, licence gate, acknowledgements, corresponding source (P1-51)

| Field | Value |
|---|---|
| Goal | `Vendor/licenses.json`: one entry per bundled component (name, version, SPDX id, licence file path inside its source tree, how it ships, upstream URL). `Scripts/licence-gate.sh` fails when: a lock entry has no manifest entry (or the reverse), a licence file is missing in `Vendor/src`, `ffmpeg -buildconf` contains `nonfree`, or a component's SPDX id is not on the allow-list (`GPL-2.0-or-later GPL-3.0-or-later LGPL-2.0-or-later LGPL-2.1-or-later BSD-2-Clause BSD-3-Clause BSD-3-Clause-Clear ISC MIT Apache-2.0 Zlib WTFPL MPL-2.0` + `LicenseRef-AOM-Patent-1.0` for SVT-AV1). `Scripts/collect-licences.sh` copies each licence text to `Vendor/out/licenses/<name>.txt` plus a generated `index.html`. `Scripts/source-bundle.sh <version>` writes `build/release/zivlet-<version>-source.tar.xz` holding: the repository at the tag (`git archive`), every tarball named in `versions.lock` (from `Vendor/downloads`, hashes re-checked), the Rust crates (`cargo vendor` output for `zivlet-svg`), and a `SOURCES.md` explaining how to rebuild. `THIRD_PARTY_NOTICES.md` moves FFmpeg, x264, libvpx, SVT-AV1, dav1d, Opus, Ogg/Vorbis, LAME, zimg, libwebp, resvg (and its crate tree, from `cargo about`-style listing produced by `cargo tree --format "{p} {l}"`), Sparkle from "Planned" to "Present". Settings › Advanced (D5) and the About panel credits link to `Contents/Resources/Licenses/index.html` |
| 05 rows | P1-51 |
| Sources | 10 §10.2–10.3, 11 §5 |

**Files:** create `Vendor/licenses.json`, `Scripts/licence-gate.sh`, `Scripts/collect-licences.sh`,
`Scripts/source-bundle.sh`, `Scripts/tests/test-licence-gate.sh`; modify `THIRD_PARTY_NOTICES.md`, `Makefile`
(`licence-gate`, `source-bundle`).

### A13.1 Failing test first

`test-licence-gate.sh` copies `versions.lock` and `licenses.json` into a temp dir and asserts the gate fails when one
manifest entry is deleted ("no licence entry for zimg"), when an SPDX id is changed to `LicenseRef-Proprietary`
("licence not allowed"), when a fake `-buildconf` contains `--enable-nonfree`; and passes on the real files after
A3. `source-bundle.sh 0.0.0-test` produces a tarball whose listing contains `ffmpeg-9.0.2.tar.xz`, `x264-…tar.bz2`,
`Vendor/build-media.sh`, `Vendor/rs/zivlet-svg/Cargo.lock`, `vendor/resvg-0.47.0/` and `SOURCES.md`.

### A13.2–A13.5

RED: scripts missing. GREEN: `make licence-gate` → `Licences OK: 13 components`. Commit `chore(release): licence
manifest, gate, acknowledgements and corresponding-source bundle`.

---

## Task A14 — Size gate and size report (P1-52)

| Field | Value |
|---|---|
| Goal | `Scripts/size-gate.sh <app> [dmg]` prints installed size (`du -sk` of the app), the per-part table (MacOS, Helpers, Frameworks/libav*, Sparkle, Resources) and the DMG size; fails above **85 MB installed / 40 MB DMG**, warns above **70 / 32** (05 P1-52) |
| Projection | App 3.4 MB (Release, M3) + media 29–30 MiB + libwebp ≈ 0.45 MB + resvg ≈ 2.2 MB + Sparkle.framework 2.9 MB (universal; 1.6 MB if thinned to arm64 with `lipo`, D-M4-11) ≈ **38–40 MB installed**; DMG ≈ 16–18 MB (the helpers alone compress to 10.0 MB in a ULMO DMG) |

**Files:** create `Scripts/size-gate.sh`, `Scripts/tests/test-size-gate.sh` (a sparse 90 MB file in a fake app fails;
a 75 MB one warns and exits 0; a 10 MB one passes; thresholds read from variables `SIZE_HARD_MB`, `SIZE_WARN_MB`,
`DMG_HARD_MB`, `DMG_WARN_MB` with the defaults above).

Commit `chore(release): size gate for the app and DMG`.
