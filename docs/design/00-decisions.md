# Zivlet — Product Decisions (locked)

Date: 2026-10-20. Decided by the project owner.

| Decision | Choice | Consequences |
|---|---|---|
| Name | **Zivlet** (formerly Satsuma; renamed 2026-10-21, see O-12a) | Own brand, icon and assets. Nothing from the reference app is reused (name, icon, sounds, screenshots, code). Check trademark/name conflicts before public launch. |
| Distribution | **Direct download only** (notarized, Developer ID), **not sandboxed** | No security-scoped folder grants. Results write beside the original directly. Updates through Sparkle 2. GPL tools may be bundled. App Store rules (no executables outside the bundle, StoreKit) do not apply. |
| License / business | **Fully free and open source** | No trial counter, no paywall, no analytics. License must be compatible with bundled GPL components (likely GPLv3). Never copy Open-Tangerine (GPLv3) code; independent implementation. |
| Minimum OS | **macOS 26+**, Apple silicon first | Native Liquid Glass (`glassEffect`), latest SwiftUI and Observation, Swift 6 strict concurrency. No pre-26 fallbacks. |

## Carried-over principles
- Zero-click flow: drag a file, tap a modifier, drop on a slice. Everything local and offline.
- Permission-free trigger where possible (no Accessibility or Input Monitoring prompts).
- Must beat the reference app on correctness (every advertised route works, e.g. WebM/Opus/AV1), transparency, speed, and extensibility.

## Defaults adopted for open items O-1…O-19 (from 10-tech-strategy §15)

Date: 2026-10-20. Adopted as working defaults so building can start; owner may override any row.

| Item | Default adopted |
|---|---|
| O-1 Licence | GPL-3.0-or-later |
| O-2 Contributions | DCO (no CLA) |
| O-3 Size | ≤ 70 MB installed / ≤ 32 MB DMG (CI gate 85 / 40) |
| O-4–O-6 | As recommended in 10-tech-strategy §15 (x264 included; LibreOffice optional verified download) |
| O-7 Document fidelity | Automatic (use LibreOffice/iWork only if already present) |
| O-8 Perl | Bundle trimmed Perl for ExifTool |
| O-9 MuPDF redaction | Decide at v2 gate |
| O-10 Bundle id | `app.zivlet.Zivlet` (domain zivlet.app) |
| O-11 Developer account | Owner action; dev builds are ad-hoc signed until available |
| O-12 Name check | Run before any public artifact. **O-12a resolved:** the product is Zivlet (formerly Satsuma, which collided with plyght/satsuma; see below) |
| O-13 Architecture | arm64-only for 1.0 |
| O-14 Output location | Beside original + Downloads fallback; more in 1.x |
| O-15 Languages | English at 1.0, strings catalogued |
| O-16 Behaviour changes | As listed (per-stream copy, 300 DPI, Ogg=Vorbis, WebM=VP9+Opus, "Already optimal", ⇧/⌘/⌃) |
| O-17 Apple Events features | Ship opt-in, off by default |
| O-18 Scope | Build phase by phase; "1.0" label only at full parity (275 pairs, 27 tools, 6 actions). Phase 2 ships as public beta. |
| O-19 Local Office fonts | Off; needs legal review |

### O-12 preliminary name check (2026-10-20)
Web search found no macOS app or file converter named "Satsuma" (the working name then). Not a trademark search; run USPTO/EUIPO class 9 search before launch. Note: Open-Tangerine uses an internal `SatsumaError` type, which may cause confusion.

**Correction (2026-10-21, post-M1 review): the check above is wrong.** `github.com/plyght/satsuma` is an MIT macOS file converter named Satsuma, and it is the codebase Open-Tangerine says it is built on. Sharing that name makes this clean-room project look derived from a codebase it must not copy, and risks a name conflict.

**[OWNER] O-12a — resolved 2026-10-21:** the product formerly called Satsuma is renamed **Zivlet** (domain zivlet.app, bundle id `app.zivlet.Zivlet`). The rename was done in one mechanical pass: `README.md`, `project.yml` (target, scheme, bundle id, O-10), `Zivlet.xcodeproj` (generated), `App/ZivletMain.swift`, `Config/Zivlet.entitlements`, the `ZivletKit` package and its `Zivlet*` modules, the logger subsystem, user defaults keys and Debug launch arguments, the `.zivlet-` staging prefix, `ZIVLET_*` environment variables, user-visible copy, and these docs. References to `github.com/plyght/satsuma` and Open-Tangerine's `SatsumaError` keep their names because they are other projects.

## Defaults adopted for plan-critique items OWN-1…OWN-7 (docs/plan/07-plan-critique.md)

| Item | Default adopted |
|---|---|
| OWN-1 Held modifier at drag start | Ignore until re-pressed (prevents Finder ⌘-move opening Tools); acting on an already-held modifier kept as a setting |
| OWN-2 Mixed-family wheel | Union of targets with "k of n" badge, max 12 slices; confirm in usability test |
| OWN-3 Tool output names | Zivlet naming spec: one-decimal speed suffix ("Speed 2.0x"), "Metadata Removed" |
| OWN-4 Reveal in Finder | On by default |
| OWN-5 PRD deliberate differences D-1…D-22 | Accepted as working spec |
| OWN-6 Published docs | Only design and plan docs are published; they stand alone |
| OWN-7 CI | Hosted runners lack Xcode 27; local `make test` is the gate until a self-hosted runner exists |

### O-12 update (2026-10-21): name conflict found
`github.com/plyght/satsuma` (MIT; an offline macOS file converter; 2 stars, last push 2026-09-16) already uses the name, and Open-Tangerine is built on it. Using "Satsuma" invited confusion with both. **Owner decision (2026-10-21): rename to Zivlet** (O-12a above).

## Owner decisions, 2026-10-21: name, feature picks, roadmap

Date: 2026-10-21. Decided by the project owner. The roadmap that turns these picks into phases is
[17-feature-roadmap.md](17-feature-roadmap.md) (with [17-roadmap-challenge.md](17-roadmap-challenge.md) and the cluster
reports 17a–17e); the requirements are in [01b-prd-additions.md](../plan/01b-prd-additions.md) and the task rows in
[05-task-list.md §9](../plan/05-task-list.md).

### (a) Name: Zivlet

| Item | Decision |
|---|---|
| Name | **Zivlet**, formerly Satsuma (O-12a above). Used everywhere: app, bundle id `app.zivlet.Zivlet`, `ZivletKit` and `Zivlet*` modules, logger subsystem, CLI `zivlet`, `.zivlet-` staging prefix, `ZIVLET_*` environment variables, docs |
| Reason | Name conflict with `github.com/plyght/satsuma`, the MIT converter Open-Tangerine is built on; sharing its name made this clean-room project look derived from it |
| Domain | zivlet.app (owner to register); zivlet.com is taken |
| Trademark | USPTO/EUIPO class 9 search **pending**; required before any public artifact (O-12, P2-119) |
| Repository | The owner plans to make the repository public as Zivlet; strict sanitisation before the first push (OWN-6) |

### (b) Feature picks

The owner dictated these picks; the wording below is the interpreted list. Two readings still need the owner's
confirmation (OWN-PICK-1 below).

| Verdict | Items |
|---|---|
| **YES** | Transcribe audio/video (English, Hindi, Hinglish; see (d)); translate a transcript to English; meeting summary with speaker labels (on device); remove silences; "ask in plain words" (on-device model, confirm); size preview while hovering a slice; Instagram/Reels presets (9:16, 4:5, 1:1); fit-to-size presets (WhatsApp, Gmail, Discord); **copy text from image (OCR, incl. Hindi): very important**; **batch rename and batch resize: important**; JPEG XL output and smaller PNG; remove image background; **PDF suite**: lock, unlock, compress, sign, merge, split ("unmerge"), remove blank pages, resize pages, make searchable (incl. Hindi); **lock/unlock other files: very important** (Word, Excel, PowerPoint, ZIP; CSV and others via encrypted ZIP; local only; only with a password the user knows); custom wheels (which slices, their order, colours); history of recent conversions (Undo, Reveal); command-line tool; Drop Box shelf (see notch below) |
| **YES, multi-file** | All confirmed, including the review-order sheet: combine anything into one PDF; photos + videos into one reel; images to animated GIF; stitch images into one long image; collage (existing) and contact sheet; join videos and join audio; batch actions on all (convert, compress, resize, rename, fit); ZIP all, with an optional password, as an Actions slice instead of a separate Compress step |
| **Multi-file priority** | Build first, in order: (1) combine anything into one PDF, (2) photos + videos reel, (3) stitch into one long image |
| **Archive scope** | **Every format, both ways**: create, extract and convert archive → archive (any → any), plus peek inside. zip, 7z, the tar family, rar input and everything else libarchive reads. RAR creation was to be investigated (decided no: OWN-ARC-1); encrypted 7z via a separate 7-Zip helper is gated (OWN-ARC-2) |
| **Notch drop box** | The Drop Box's primary home is the MacBook notch: while dragging files toward the notch it expands into a tray; drop to stash; hover or click to reopen; bulk actions (Share/AirDrop, Copy, Move, Zip, Convert all, Clear). References files by default, survives relaunch, optional auto-clear. Uses the existing permission-free drag sampler (no Accessibility). Displays without a notch get a top-centre pill; per screen on externals; Reduce Motion honoured. Prior art described in our own words only |
| **YES, build last** | Choosable picker style (Wheel or Bar) and place (at cursor or at the notch), sharing the notch infrastructure |
| **LATER** | Watch folders; video/audio extras group (highlights, extract audio, normalise, screen recording → GIF) |
| **NO** | Text to speech; filler-word removal; burn-in subtitles; "Replace" (unclear, treated as not needed) |

### (c) Roadmap owner decisions (17-feature-roadmap §14), adopted at their recommendations

All 29 items are adopted as recommended. Where the challenge pass amended a recommendation
(17-roadmap-challenge §12), the amended form is the one adopted.

| ID | Decision adopted |
|---|---|
| OWN-PLAN-1 | Phase 2 ships as three public betas (0.5 / 0.6 / 0.7); apply the challenge re-sizes; keep the §4.3 cut list ready (Phase 2 is about 2× its original size) |
| OWN-PLAN-2 | Make Searchable, Remove Blank Pages and Page Size stay in 0.7; visual signature stays at the start of Phase 3 |
| OWN-W-1 | Actions wheel grows to 9 (ZIP, LOCK, RENAME added); Lock/Unlock is one slot |
| OWN-PDF-1 | Allow non-ASCII PDF passwords, with a warning and an "opens on Mac" check result |
| OWN-PDF-2 | Visual signatures in Phase 3; PAdES B-B digital signatures as a Phase 4 gate |
| OWN-PDF-3 | Remove Blank Pages removes only "blank" pages and lists "nearly blank" ones for review |
| OWN-PDF-4 | Bundle Noto Sans Devanagari (OFL-1.1, ≤ 0.4 MB, separate resource) for the text layer |
| OWN-PDF-5 | Honour PDF permission bits unless the owner password is given (Copy Text/Searchable for extraction; Merge/Split/Organize/Page Size/No Blanks for assembly/modification); Compress keeps encryption as is |
| OWN-LK-1 | Policy approved: no password recovery or bypass; passwords never stored |
| OWN-LK-2 | Legacy .doc/.xls/.ppt unlock in Phase 3, after the LK-M3 fixtures exist |
| OWN-LK-3 | Office edit-restriction removal with a verified password: optional, Phase 4 |
| OWN-ARC-1 | No RAR creation |
| OWN-ARC-2 | 7-Zip helper for encrypted 7z is a Phase 3 gate, decided on demand, and stays closed until passwords can reach it without argv |
| OWN-APP-1 | Label BOX; drops go to the most recent box |
| OWN-APP-2 | Notch tray is the Drop Box's primary home; shake-to-open is opt-in in Phase 2 |
| OWN-APP-3 | Owned-copy storage warning at 2 GB; auto-clear off by default |
| OWN-APP-4 | No "More…" overflow slice for now (decide after the usability test); O-18 parity counts tools as "reachable" (wheel, custom wheel, App Intents, CLI) |
| OWN-APP-5 | History keeps 30 days / 500 entries, excluded from Time Machine; "Off" keeps 24 h of undo data; the menu-bar Recent list stays at 20 |
| OWN-APP-6 | CLI subset in 0.7; own Homebrew tap first |
| OWN-IMG-1 | JPEG XL output decided after the measured DMG; accept ≈ 74 MB if needed |
| OWN-MA-1 | Discord preset at 20 MB (19.4 MB target); the 10 MB preset is dropped |
| OWN-MA-2 | Drop the WhatsApp 100 MB "document" preset (Business API only); keep 15.5 MB media |
| OWN-MA-3 | Meeting summaries in English only at first |
| OWN-MA-4 | Speaker pack via CoreML as a data-only download, after P3-190 measures it; sherpa-onnx is a test baseline only, never a shipped fallback |
| OWN-MA-5 | "Ask in plain words" confirmed for Phase 4 (needs Apple Intelligence on the Mac) |
| OWN-QA-1 | Manual checks with the owner's apps (Word/Excel/PowerPoint, iWork, Archive Utility, a Windows 11 VM, real Gmail and WhatsApp sends, real Hindi scans) scheduled before 0.5 (lock) and 0.6 (presets) |
| OWN-SIZE-1 | Keep the 70 MB target (NFR-7, no re-baseline); decide on any overage from the measured P1-52 DMG |
| OWN-OCR-1 | If macOS 26.x lacks Vision Hindi, hide Hindi below 27 and say why; revisit only if P2-190 fails on 26.x |
| OWN-PICK-1 | Interpretations adopted: "JPEG XL" (not Excel output) and "remove *image* background" (not PDF background or watermark removal); the owner may still correct them |

### (d) Transcription

| Item | Decision |
|---|---|
| Languages | English, Hindi, Hinglish and mixes of them |
| Output | **Both files** for Hindi/Hinglish: one in Roman script and one in Devanagari (English words kept in Roman); one file for pure English |
| Design | Pending in `docs/design/16-transcription.md` (not yet written). The roadmap only reserves the slot: P3-111, FR-138, a `TRANSCRIBE` slice, History kind `transcribe`, CLI verb `zivlet transcribe` |
