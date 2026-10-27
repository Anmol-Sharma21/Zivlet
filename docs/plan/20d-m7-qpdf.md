# 20d — M7 Stream C: qpdf in the worker (P2-13)

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Decisions: D-M7-16,
D-M7-17. Prototype: index §3.1 (blocked; see G-M7-1). Gap audit: index §2.6. Design: [design/13](../design/13-image-pdf-engine.md)
§4.4, [design/17a](../design/17a-pdf.md) D-PDF-5 and D-PDF-8, [design/10](../design/10-tech-strategy.md) §9–§10,
[02-architecture](02-architecture.md) §4 (`EnginePDF`, `CQPDF`). Swift and C++ below are specification-grade and were
not compiled.

Acceptance being built. 05 P2-13: qpdf + libjpeg-turbo → `CQPDF.xcframework`; licence entries; a smoke test rewrites a
PDF. 05 §9.1 adds: built with `-DREQUIRE_CRYPTO_NATIVE=ON` and **no OpenSSL** (D-PDF-8); the smoke test decrypts an
RC4 fixture (PDFKit-made) and an AES-256 fixture; `otool -L` shows no libcrypto; qpdf is static, so the size check is
"qpdf + libjpeg-turbo contribution ≤ 4.5 MB" (10 §9). The brief adds: pinned version and SHA-256, arm64, minos 26.0,
no GnuTLS, `-ffile-prefix-map`; used inside the worker through the library API, never a qpdf command line with a
password; `THIRD_PARTY_NOTICES`, licence texts in the bundle, corresponding-source bundle, size gate, release-check and
licence-gate updated.

Pins measured this session (D-M7-17). Both are the latest stable releases on 2026-10-27; the tarballs are in
`Vendor/downloads/<name>-<version>/` (untracked), each SHA-256 computed here, and each upstream OpenPGP signature
verified in a throwaway keyring:

| Name | Version | URL | SHA-256 | Signer fingerprint |
|---|---|---|---|---|
| qpdf | 12.4.2 (2026-09-27) | `https://github.com/qpdf/qpdf/releases/download/v12.4.2/qpdf-12.4.2.tar.gz` | `8a58af5b6141319287c1883bec8bd1bd545b7567b7fc5e6ce5d25a1c85f36397` (equals the signed `qpdf-12.4.2.sha256`) | `C2C96B10011FE009E6D1DF828A75D10998012C7E` (`.tar.gz.asc` and the signed `.sha256` both valid) |
| libjpeg-turbo | 3.2.0 (2026-06-30) | `https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz` | `6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e` | `0338C8D8D9FDA62CF9C421BD7EC2DBB6F4DBF434` (`.tar.gz.sig` valid) |

10 §10 said libjpeg-turbo 3.1.x; 3.2.0 is the current stable line, so the pin moves (D-M7-17). The keys came from
`keyserver.ubuntu.com` (qpdf; the `keys.openpgp.org` copy has no user ID and gpg refused it) and `keys.openpgp.org`
(libjpeg-turbo); C1 commits them as `Vendor/keys/qpdf.asc` and `Vendor/keys/libjpeg-turbo.asc`.

Why a C++ shim instead of `qpdfjob` JSON (D-M7-16), read from the qpdf 12.4.2 sources:
- `QPDFJob::doCheck` (the `--check` path) calls `showEncryption`, which prints `User password = <the user password>`
  when the owner password was given (`libqpdf/QPDFJob.cc`). The job JSON output's `encrypt` key also carries a
  recovered user password. So `--check`, `--show-encryption` and `--json` must never run with a password, and their
  output can never be logged.
- The plain C API (`qpdf-c.h`) can read, check and write R6, but it has no `ownerPasswordMatched`,
  `userPasswordMatched` or the R/V/method values that the unlock rule (OWN-LK-1) and the verify step need.
- `QPDF::isEncrypted(R, P, V, stream, string, file)`, `ownerPasswordMatched()`, `userPasswordMatched()`,
  `QPDFWriter::setR6EncryptionParameters(...)`, `setPreserveEncryption(false)` and the global limits
  (`qpdf::global::limits`, new in 12.x: nesting, container size, errors, stream filters) give everything.
- A small C++ file of our own with a C header keeps Swift free of C++ interop (13 §4.4's reason for `qpdfjob`).

---

## Task C1 — Pins, keys and provenance

| Field | Value |
|---|---|
| Goal | `Vendor/versions.lock` gains `qpdf 12.4.2` and `libjpeg-turbo 3.2.0` (URL and SHA-256 above); `Vendor/signatures.lock` gains both signature URLs and fingerprints; `Vendor/keys/qpdf.asc` and `Vendor/keys/libjpeg-turbo.asc`; `Vendor/PROVENANCE.md` gets the two rows (date, where the keys came from, both checks) |
| Acceptance | `Vendor/fetch.sh --only qpdf` and `--only libjpeg-turbo` print "verified" (the files are already in `Vendor/downloads`, so nothing is downloaded again); `Vendor/verify-sources.sh` prints "signed by …" for all four signed sources; `Vendor/tests` lock tests pass |
| Effort | S |

**Files:** `Vendor/versions.lock`, `Vendor/signatures.lock`, create `Vendor/keys/qpdf.asc`,
`Vendor/keys/libjpeg-turbo.asc`; `Vendor/PROVENANCE.md`.

RED: `Vendor/verify-sources.sh` → "qpdf is not in versions.lock" after adding the signature line first. Commit
`build(vendor): pin qpdf 12.4.2 and libjpeg-turbo 3.2.0 with their signatures`.

---

## Task C2 — Build `CQPDF.xcframework` once and cache it

**Owner step first: OS-M7-1.** In this planning session the auto-mode permission check refused to run the upstream
build (`cmake` on the downloaded sources), so nothing was built or measured. C2 runs only after the owner allows it
or runs the build. The script is the prototype's (index §3.1), moved into `Vendor/`.

| Field | Value |
|---|---|
| Goal | `Vendor/build-native.sh qpdf`: libjpeg-turbo (`ENABLE_SHARED=OFF`, `WITH_TURBOJPEG=OFF`, `WITH_TOOLS=OFF`, `WITH_TESTS=OFF`) then libqpdf (`BUILD_SHARED_LIBS=OFF`, `BUILD_STATIC_LIBS=ON`, `REQUIRE_CRYPTO_NATIVE=ON`, `USE_IMPLICIT_CRYPTO=OFF`, `BUILD_DOC=OFF`, `INSTALL_EXAMPLES=OFF`, `STATIC_JPEG=ON`, libjpeg from `Vendor/prefix`, zlib from the SDK's `libz.tbd`), target `libqpdf_static` only; Xcode's clang (`xcrun -f clang`), `-arch arm64 -mmacosx-version-min=26.0`, `-ffile-prefix-map` for the source, build and prefix folders, `SOURCE_DATE_EPOCH` and `ZERO_AR_DATE=1`, `PKG_CONFIG_LIBDIR` limited to `Vendor/prefix`, `CMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local`, `CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF`; `xcrun libtool -static` merges `libqpdf.a` + `libjpeg.a` into `libCQPDF.a`; headers `qpdf/*.h*` with a module map **not** exported to Swift (the shim includes them; Swift imports only the shim, C4); `package_xcframework CQPDF` (existing helper) writes `Vendor/out/CQPDF.xcframework` and `CQPDF.sha256`; `Vendor/cache-key.sh` gets a `CQPDF` input list (the two tarball hashes, the script, the Xcode version) and `Vendor/ensure-native.sh` builds it when the key changed, never otherwise. Logs in `Vendor/logs/` with the build time and the load average |
| Acceptance | `nice -n 10 Vendor/build-native.sh qpdf` once, in the background (the only from-source build in M7; existing components are never rebuilt); a second `Vendor/ensure-native.sh` prints "up to date"; `Vendor/pack.sh` includes `CQPDF.xcframework` in the cached vendor tarball |
| Effort | M (build time unknown: not measured, G-M7-1) |

**Files:** `Vendor/build-native.sh`, `Vendor/cache-key.sh`, `Vendor/ensure-native.sh`, `Vendor/pack.sh` (if its list is
explicit), `Vendor/tests/test-*.sh` (the cache-key case).

RED: `Vendor/build-native.sh qpdf` → "usage: build-native.sh libwebp". Commit `build(vendor): a static CQPDF
xcframework with native crypto only`.

---

## Task C3 — `verify-native.sh`: what the library may and may not contain

| Field | Value |
|---|---|
| Goal | `Vendor/verify-native.sh CQPDF` checks the archive: every object is arm64 only (`lipo -archs`); every object's `LC_BUILD_VERSION` minos is 26.0 (`vtool -show-build` / `otool -l`); no undefined symbol from OpenSSL or GnuTLS (`nm -u` has no `EVP_`, `SSL_`, `gnutls_`); the native crypto provider is present (`QPDFCrypto_native` symbols defined); no string with the build machine's paths (`strings` has no `/Users/`, `/private/tmp`, `/opt/homebrew`); and after C5 the **worker binary**'s `otool -L` lists no `libcrypto`, `libssl` or `gnutls` and only `/usr/lib` and `/System` libraries |
| Acceptance | `Vendor/tests/test-verify-native.sh` with tiny objects compiled at test time from our own C files: an x86_64 object, a minos-14 object, an object referencing `EVP_CIPHER_CTX_new`, and an object with an embedded `/Users/x` string each make the script fail with its own message; a clean arm64/26.0 object passes |
| Effort | S |

**Files:** create `Vendor/verify-native.sh`, `Vendor/tests/test-verify-native.sh`; `Scripts/release-build.sh` or
`check-bundle.sh` (the worker `otool -L` part).

RED: the test script fails: `verify-native.sh: No such file`. Commit `build(vendor): check CQPDF for architecture,
deployment target, crypto and paths`.

---

## Task C4 — `CZivletPDF`: the shim, and `EnginePDF`'s first test

| Field | Value |
|---|---|
| Goal | SwiftPM C++ target `CZivletPDF` (`cxxLanguageStandard: .cxx20`, links `CQPDF`, `c++`, `z`) with a C header `zivlet_pdf.h`: `zv_pdf_inspect(path, password, len, limits, *out)`, `zv_pdf_check(path, password, len, *out)` (QPDFWriter to `Pl_Discard` with `qpdf_dl_all` plus the page and helper traversal of `doCheck`, **without** `showEncryption`), `zv_pdf_write(path, password, len, mode, params, out_path, *err)` with modes `preserve`, `decrypt`, `encryptR6`; passwords arrive as `(const uint8_t*, size_t)`; the shim copies them into a `std::string` only as long as qpdf needs and wipes that string's buffer with `memset_s` before it is destroyed (qpdf's own internal copies are not reachable, recorded best effort); every C++ exception is caught and mapped to an error code (`ZV_PDF_WRONG_PASSWORD` from `qpdf_e_password`, `ZV_PDF_DAMAGED`, `ZV_PDF_UNSUPPORTED_ENCRYPTION` for non-Standard security handlers, `ZV_PDF_LIMIT`, `ZV_PDF_IO`, `ZV_PDF_INTERNAL`); warnings are counted, never printed (`setSuppressWarnings(true)`); a qpdf logger that discards info output is installed so nothing reaches stdout/stderr. New module `EnginePDF` (strict, Foundation + PDFKit + `CZivletPDF`) wraps it in Swift: `QPDFDocumentReader`, `QPDFWriterBridge` returning typed `PDFEngineError` |
| Acceptance | `EnginePDFTests.QPDFSmokeTests` on PDFs generated at test time (index §3.2 shows CoreGraphics on this SDK writes RC4-40 as V2 R3 at key length 40 and AES-128 as V4 R4 at 128; it cannot write RC4-128, and refuses a non-ASCII password by returning no context): (1) a plain two-page CoreGraphics PDF is rewritten (`preserve`), the output opens in PDFKit with 2 pages and `zv_pdf_check` passes (05's "rewrites a PDF"); (2) the RC4-40 fixture and the AES-128 fixture (CoreGraphics, user + owner passwords) decrypt with the user password and report R 3 / R 4 and the right methods; (3) an AES-256 fixture written by the shim (`encryptR6`) decrypts and reports R 6 / AESv3 (05 §9.1's AES-256 case); (4) a wrong password → `.wrongPassword`; (5) nothing is printed to stdout or stderr during (1)–(4) (the test redirects both to pipes and expects them empty) |
| Effort | M |

**Files:** `Package.swift` (binary target `CQPDF`, targets `CZivletPDF`, `EnginePDF`, test target `EnginePDFTests`;
`EnginePDF` added to `ZivletWorkerKit`, **not** to the `ZivletKit` product's app-facing list, C5), create
`Sources/CZivletPDF/include/zivlet_pdf.h`, `Sources/CZivletPDF/zivlet_pdf.cc` (< 800 lines; split into
`zivlet_pdf_inspect.cc`, `zivlet_pdf_write.cc` if it grows), `Sources/EnginePDF/QPDFDocumentReader.swift`,
`QPDFWriterBridge.swift`, `PDFEngineError.swift`, `Tests/EnginePDFTests/QPDFSmokeTests.swift`,
`Tests/EngineTestSupport/PDFFixtures.swift` (CoreGraphics fixtures, our own words); `Scripts/coverage.sh`
(`GATED_MODULES` += `EnginePDF`; the C++ shim's lines are reported beside it and gated at 80 % too, D-M7-16).

```swift
@Test func aCoreGraphicsRC4FileOpensWithItsUserPassword() throws {
    let dir = try TempDir()
    let url = try PDFFixtures.encrypted(in: dir, keyLength: 40, user: "u-pass", owner: "o-pass")
    let info = try QPDFDocumentReader.inspect(url, password: JobSecret(utf8: "u-pass"), limits: .standard)
    #expect(info.encryption == .standard(revision: 3, version: 2, streams: .rc4))
    #expect(info.matched == .user)
}
```

RED: `no such module 'EnginePDF'`. Commit `feat(pdf): qpdf through a small shim of our own, with a smoke test`.

---

## Task C5 — Worker only (D-M7-16)

| Field | Value |
|---|---|
| Goal | `Worker/main.swift` hosts `PDFEngine()` beside `ImageEngine()`; `ZivletRuntime` does **not** depend on `EnginePDF` (the PDF job values it needs live in `ZivletEngineKit`, E2); the app's in-process fallback has no PDF engine, so a PDF tool with the worker unavailable fails with `engineMissing(.pdf)` → "PDF tools need Zivlet's converter, which isn't available. Restart Zivlet." *new*. `EngineID` gains `pdf` |
| Acceptance | `check-bundle.sh` (or a new release-check step) asserts: the worker binary defines qpdf symbols (`nm` finds `QPDFWriter`); the app binary does not; neither links a crypto library; `make release-check` passes; a `WorkerSelection` unit test: with the worker down, a PDF tool job fails with `engineMissing(.pdf)` and its copy |
| Effort | S |

**Files:** `Package.swift`, `project.yml` (nothing new if `ZivletWorkerKit` carries `EnginePDF`), `Worker/main.swift`,
`Sources/ZivletCore/Jobs/JobIdentity.swift`, `Sources/ZivletRuntime/JobErrorCopy.swift`,
`Sources/ZivletRuntime/WorkerSelection.swift`, `Scripts/check-bundle.sh`, `Scripts/tests/test-check-bundle.sh`.

RED: `type 'EngineID' has no member 'pdf'`. Commit `feat(worker): the PDF engine runs only in the worker`.

---

## Task C6 — Licences, notices, source bundle, size

| Field | Value |
|---|---|
| Goal | `Vendor/licenses.json`: `qpdf` (`Apache-2.0`, files `LICENSE.txt`, `NOTICE.md`; ships "inside ZivletWorker, static"), `libjpeg-turbo` (`IJG AND BSD-3-Clause AND Zlib`, files `LICENSE.md`, `README.ijg`; ships "inside ZivletWorker, static, through qpdf"); `Scripts/licence-gate.sh` allow-list gains `IJG` (`Apache-2.0` and `Zlib` are on it already; qpdf's NOTICE also lets a user keep treating it as Artistic-2.0, the licence of releases before 7, and its bundled `qtest` test tool is Artistic-2.0; Zivlet takes qpdf under `Apache-2.0`, ships no `qtest`, and reproduces `NOTICE.md` verbatim); `Scripts/collect-licences.sh` copies the texts (Apache NOTICE verbatim, 10 §10) into `Contents/Resources/Licenses`; `THIRD_PARTY_NOTICES.md` gets both entries in the existing format; `Scripts/source-bundle.sh` needs no change if it reads every `versions.lock` tarball (checked by its script test, which gains the two names); the size gate prints the worker's size before and after, and the qpdf + libjpeg-turbo contribution (worker size with minus without, from a build with and one without `EnginePDF`) is compared with 10 §9's expected 4.5 MB (worst 6 MB) |
| Acceptance | `make licence-gate` prints 15 components; `Scripts/tests/test-licence-gate.sh` gains a case where `licenses.json` lacks qpdf → fails; the built app has `Licenses/qpdf.txt` and `Licenses/libjpeg-turbo.txt`; `test-source-bundle` (if present) or a new case lists both tarballs; the size row in the record states the measured contribution and whether it is within 4.5 MB (if over, OS-M7 asks, OWN-SIZE-1/2) |
| Effort | S |

**Files:** `Vendor/licenses.json`, `Scripts/licence-gate.sh`, `Scripts/collect-licences.sh`, `THIRD_PARTY_NOTICES.md`,
`Scripts/tests/test-licence-gate.sh`, `Scripts/source-bundle.sh` (only if needed).

RED: `make licence-gate` → "qpdf in versions.lock has no licences.json entry". Commit `docs(licences): qpdf and
libjpeg-turbo notices and texts in the bundle`.

---

## Decisions of this stream (copied to index §4)

| ID | Decision |
|---|---|
| D-M7-16 | qpdf ships static in `CQPDF.xcframework` (libqpdf + libjpeg-turbo, native crypto only), linked only into the worker through `EnginePDF` and our own C++ shim `CZivletPDF` with a C header. No in-process PDF fallback (untrusted PDFs never reach qpdf in the app, 02 P3). Never `qpdfjob` with `--check`, `--show-encryption` or `--json` and a password, because they print the user password; the shim's check is its own. No qpdf child process, so no argv can carry a password |
| D-M7-17 | qpdf 12.4.2 and libjpeg-turbo 3.2.0 (latest stable on 2026-10-27; 10 §10's 3.1.x moves to 3.2.0), pinned by SHA-256 and upstream signature, built once under `nice -n 10` and cached in `Vendor/out` like CWebP |
