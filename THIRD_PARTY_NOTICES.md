# Third-party notices

Zivlet is licensed GPL-3.0-or-later (see `LICENSE`). This file lists the third-party components Zivlet uses today and
the ones it plans to bundle, with their licences. When a component is actually bundled, its full licence text and any
NOTICE file will ship inside the app (About › Acknowledgements and `Contents/Resources/Licenses/`). The source release
for each version will include the corresponding source GPL requires.

Versions in the planned table are the current targets and may change before they are vendored.

## Present

Zivlet doesn't distribute any third-party code yet. The app links only Apple system frameworks (AppKit, SwiftUI,
ImageIO, Core Graphics, Quartz Core, AudioToolbox, Carbon HIToolbox, CryptoKit, Foundation) and the Swift runtime
libraries that ship with macOS.

Tools used during development, not distributed with Zivlet:

| Component | Licence (SPDX) | Use |
|---|---|---|
| FFmpeg / ffprobe | GPL or LGPL, depending on how your copy was built | Debug builds and `make smoke` use an ffmpeg you install yourself (`ZIVLET_FFMPEG_DIR` or Homebrew). Release builds never use it |
| XcodeGen | MIT | Generates `Zivlet.xcodeproj` from `project.yml` |
| swift-format | Apache-2.0 | `make format` / `make lint` (ships with the Xcode toolchain) |

## Planned

| Component | Target version | Licence (SPDX) | How it will ship | Notes |
|---|---|---|---|---|
| FFmpeg (libav\*, ffmpeg, ffprobe) | 9.0.x | GPL-3.0-or-later (built with `--enable-gpl --enable-version3`) | bundled helpers + shared libraries | Network protocols disabled. This GPL build is one reason Zivlet is GPL-3.0-or-later |
| x264 | stable | GPL-2.0-or-later | inside libavcodec | |
| libvpx | 1.17 | BSD-3-Clause | inside libavcodec | |
| SVT-AV1 | 4.x | BSD-3-Clause-Clear + AOMedia Patent License 1.0 | inside libavcodec | |
| dav1d | 1.5 | BSD-2-Clause | inside libavcodec | |
| Opus | 1.6 | BSD-3-Clause | inside libavcodec | |
| libogg / libvorbis | 1.3 | BSD-3-Clause | inside libavcodec | |
| LAME | 3.100 | LGPL-2.0-or-later | inside libavcodec | |
| zimg | 3.0 | WTFPL | inside libavfilter | |
| libwebp (+ mux, sharpyuv) | 1.6 | BSD-3-Clause | static | WebP output |
| libarchive | 3.8 | BSD-2-Clause | static | Archive read, write and conversion |
| xz (liblzma) / zstd / lz4 | 5.8 / 1.5 / 1.10 | 0BSD / BSD-3-Clause / BSD-2-Clause | static | Compression filters for libarchive |
| 7-Zip (`7zz` helper) | 26.x | LGPL-2.1-or-later AND BSD-3-Clause | separate helper | Built with the RAR code removed. Zivlet ships no unRAR code |
| qpdf | 12.x | Apache-2.0 | static | PDF lock, unlock, merge, split. NOTICE reproduced |
| libjpeg-turbo | 3.1 | IJG AND BSD-3-Clause AND Zlib | static (with qpdf) | |
| ExifTool | 13.x | Artistic-1.0-Perl OR GPL-1.0-or-later | Perl scripts in Resources | Metadata. Used under the GPL option |
| Perl (trimmed) | 5.42 | Artistic-1.0-Perl OR GPL-1.0-or-later | helper | Runs ExifTool |
| libimagequant | 4.x | GPL-3.0-or-later | static | PNG quantisation |
| oxipng | 10.x | MIT | static | Lossless PNG optimisation |
| resvg / usvg / tiny-skia | 0.47 | Apache-2.0 OR MIT; tiny-skia BSD-3-Clause | static | SVG rendering |
| krilla / pdf-writer | 0.8 / 0.15 | MIT OR Apache-2.0 | static | PDF writing |
| Sparkle | 2.x | MIT (includes bsdiff, BSD-2-Clause) | framework | Updates. Full LICENSE reproduced |
| swift-argument-parser | 1.x | Apache-2.0 WITH Swift-exception | Swift package | Command-line interface |
| swift-subprocess | 1.x | Apache-2.0 WITH Swift-exception | Swift package | |
| ZIPFoundation | 0.9 | MIT | Swift package | |
| KeyboardShortcuts | 3.x | MIT | Swift package | |
| Carlito / Caladea / Selawik | upstream | OFL-1.1 | fonts | Document rendering. OFL text shipped unmodified |

Gated components need the owner's approval before they are adopted:

| Component | Licence (SPDX) | Notes |
|---|---|---|
| MuPDF | AGPL-3.0-or-later | Separate helper, if adopted |
| libjxl (+ highway, brotli) | BSD-3-Clause; Apache-2.0; MIT | JPEG XL, only if the size budget allows |
| LibreOffice | MPL-2.0 (parts LGPL-3.0-or-later) | Optional download from The Document Foundation on request. Never bundled or modified |

## Not accepted

These are never bundled:

- fdk-aac (non-free licence);
- unRAR (its licence is not GPL-compatible);
- any ffmpeg built with `--enable-nonfree`.
