# Where the vendored source pins come from

`Vendor/versions.lock` pins every source tarball by SHA-256, and `Vendor/fetch.sh` refuses any download that does
not match. The hashes were measured when the pins were written (2026-10-21), which on its own is trust on first use.
This file records the second, independent check of each pin. Repeat it whenever a pin changes, and update the table.

Checked on 2026-10-22:

| Source | Second check | Result |
|---|---|---|
| ffmpeg 9.0.2 | OpenPGP signature `ffmpeg-9.0.2.tar.xz.asc` by the FFmpeg release signing key `FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8` (key from ffmpeg.org, in `Vendor/keys/ffmpeg.asc`) | good signature (`Vendor/verify-sources.sh`) |
| libwebp 1.6.0 | OpenPGP signature `libwebp-1.6.0.tar.gz.asc` by the WebP release signing key `6B0E 6B70 976D E303 EDF2 F601 F9C3 D6BD B823 2B5D` (key from keyserver.ubuntu.com, in `Vendor/keys/libwebp.asc`) | good signature; the hash also equals Homebrew's `webp` 1.6.0 formula |
| libvpx 1.17.0 | Homebrew `libvpx` 1.17.0 formula (same URL) | same SHA-256 |
| SVT-AV1 4.2.0 | Homebrew `svt-av1` 4.2.0 formula (same URL) | same SHA-256 |
| dav1d 1.5.4 | Homebrew `dav1d` 1.5.4 formula (same URL) | same SHA-256 |
| zimg 3.0.6 | Homebrew `zimg` 3.0.6 formula (same URL) | same SHA-256 |
| LAME 3.100 | Debian `lame_3.100-6.dsc` (`lame_3.100.orig.tar.gz` is the upstream tarball) | same SHA-256 |
| libogg 1.3.6, libvorbis 1.3.7, opus 1.6.1 | Xiph's published `SHA256SUMS` | same SHA-256 |
| Sparkle 2.10.0 tools | GitHub's digest of the release asset `Sparkle-2.10.0.tar.xz` | same SHA-256 |
| x264 b35605ac | none: the pin is a GitLab archive of a commit, which has no published hash or signature and is not guaranteed to stay byte-identical. The commit exists upstream (GitLab API) | open (G-M4-6) |

Not pinned by content yet (open, G-M4-6): the Rust toolchain is checked by its version string only
(`Vendor/rust-toolchain.txt`, `Vendor/build-rs.sh`), and the Homebrew build tools that `Vendor/check-tools.sh`
requires are checked for presence, not version or hash. The crates are pinned by `Cargo.lock` and built with `--locked`.
