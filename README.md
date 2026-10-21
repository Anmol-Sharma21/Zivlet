# Zivlet

Zivlet is a free, open-source file converter for macOS. Start dragging files in Finder, tap a modifier key (⇧, ⌘
or ⌃), and a Liquid Glass radial wheel opens at the pointer. Drop the files on a slice to convert them. The output
appears next to the original, and you never open an app window.

- Licence: GPL-3.0-or-later.
- Platform: macOS 26 or later, Apple silicon.
- Local and offline: your files never leave your Mac.
- No telemetry, no accounts, no cloud services.

## Status

**Pre-alpha. Nothing has been released yet.** There is no signed or notarized build.

| Milestone | What it contains | State |
|---|---|---|
| M1 | Repository skeleton and the pure core logic (format catalog, output naming, trigger and wheel models, media planners) | done |
| M2 | The drag-and-tap trigger and the radial wheel, running in a development build | done |
| M3 | First end-to-end image, audio and video conversions: images through ImageIO and Quartz in-process, audio and video through a development ffmpeg. A result HUD shows progress, Cancel, Undo and Reveal | code complete; owner QA outstanding |
| M4 | Private alpha 0.1: the full Phase 1 conversion matrix, bundled engines, a notarized DMG and updates | planned |

## Build

You need Xcode 27 at `/Applications/Xcode.app`, XcodeGen and the tools that build the vendored libraries (libwebp,
the resvg-based SVG renderer and, for `make vendor`, FFmpeg with its codecs):

```sh
brew install xcodegen cmake meson ninja autoconf automake libtool pkgconf rust
```

`Vendor/check-tools.sh` names anything missing. Export `DEVELOPER_DIR` before you run `swift`, `xcodebuild` or `make`.
(`Scripts/env.sh` falls back to the same path, but don't rely on it.)

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

| Step | Command |
|---|---|
| Unit tests | `make test` (runs `swift test` in `Packages/ZivletKit`) |
| Coverage gate | `make coverage` (fails if any gated module drops below 80 % line coverage) |
| Lint | `make lint` (`swift format lint --strict` plus a log-privacy check). `make format` fixes formatting |
| App | `make app` (XcodeGen generates `Zivlet.xcodeproj` from `project.yml`, then xcodebuild builds an ad-hoc-signed Debug app under `build/DerivedData`) |
| ffmpeg smoke test (opt-in) | `ZIVLET_FFMPEG_DIR=<dir> make smoke` (`<dir>` must contain `ffmpeg` and `ffprobe`) |
| Vendored libraries | `make test`, `coverage`, `app` and `release-check` first build `CWebP` and `CZivletSVG` into `Vendor/out` when they are missing or stale (about 25 s on a clean clone). Sources are downloaded into `Vendor/downloads` and checked against the SHA-256 in `Vendor/versions.lock` |
| Media helpers | `make vendor` builds FFmpeg 9.0.2 and its codec libraries (about 3 minutes clean) and stages and checks them; `make vendor-test` runs the vendor script tests |

Every app build copies the vendored `ffmpeg` and `ffprobe` (from `make vendor`) into `Contents/Helpers` and their
libraries into `Contents/Frameworks`. A Debug build looks for ffmpeg in this order:

1. the app's bundled helpers;
2. the directory named by `ZIVLET_FFMPEG_DIR`;
3. a Homebrew install (`brew install ffmpeg`).

Without `make vendor`, a Debug build warns and uses 2 or 3; a Release build fails. Release builds trust only the
bundled helpers: `make release-check` builds the media helpers if needed, then fails if a Release build refers to a
Homebrew path or its bundle misses a helper or library. Image conversions don't need any external tool.

## Roadmap

| Phase | Release | Focus |
|---|---|---|
| 1 | 0.1 private alpha (M4) | Image, audio and video conversions; bundled engines; notarized DMG |
| 2 | 0.5–0.7 public betas | OCR copy-text, lock/unlock, PDF basics, more image tools, multi-file features, a Drop Box, custom wheels, history, archives |
| 3 | 1.0 | Signatures, legacy Office unlock, custom-wheel colours and import/export, the full CLI, local transcription |
| 4 | 1.x | Meeting notes with speaker labels, requests in plain words, smart crop and more |

Every feature runs on your Mac. For the details, see:

- [docs/design/17-feature-roadmap.md](docs/design/17-feature-roadmap.md): phases, effort, licences and size;
- [docs/plan/05-task-list.md](docs/plan/05-task-list.md): milestones and task rows.

## Clean room

Independent, clean-room project inspired by the public behaviour of Tangerine for Mac; not affiliated with or endorsed by its developer.

Zivlet contains no code, assets, sounds, icons, UI strings or screenshots from that app (called "the reference app"
elsewhere in this repository). The behaviour is written up in `docs/`, in the project's own words.
[CONTRIBUTING.md](CONTRIBUTING.md) sets out the rule contributors follow.

## Contributing and security

- Contributions are accepted under the Developer Certificate of Origin. See [CONTRIBUTING.md](CONTRIBUTING.md).
- Report vulnerabilities privately. See [SECURITY.md](SECURITY.md).
- Third-party components and their licences are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Licence

Zivlet is free software. You can redistribute it and/or modify it under the terms of the GNU General Public License
as published by the Free Software Foundation, either version 3 of the License or (at your option) any later version.
See [LICENSE](LICENSE).
