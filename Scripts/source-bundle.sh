#!/usr/bin/env bash
# Corresponding-source bundle for a release (P1-51, GPL-3.0 §6): build/release/zivlet-<version>-source.tar.xz with
#   zivlet-<version>/   the repository at ZIVLET_SOURCE_REF (default HEAD; the release workflow passes the tag)
#   upstream/           every tarball named in Vendor/versions.lock (laid out like Vendor/downloads), hashes checked
#   vendor/             the Rust crates of zivlet-svg (cargo vendor --versioned-dirs)
#   SOURCES.md          how to rebuild the bundled binaries from these files
# Usage: Scripts/source-bundle.sh <version>
set -euo pipefail
source "$(dirname "$0")/env.sh"
VERSION=${1:?usage: source-bundle.sh <version>}
[[ "$VERSION" =~ ^[0-9A-Za-z.+-]+$ ]] || { echo "error: bad version $VERSION" >&2; exit 2; }
REF=${ZIVLET_SOURCE_REF:-HEAD}
RELEASE=${ZIVLET_RELEASE_DIR:-$REPO_ROOT/build/release}
DOWNLOADS=$REPO_ROOT/Vendor/downloads
CARGO_HOME=${ZIVLET_CARGO_HOME:-$REPO_ROOT/Vendor/downloads/cargo-home}
NAME=zivlet-$VERSION-source
mkdir -p "$RELEASE"
WORK=$(mktemp -d "$RELEASE/.source.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/$NAME/upstream"

git -C "$REPO_ROOT" archive --format=tar --prefix="zivlet-$VERSION/" "$REF" | tar -xf - -C "$WORK/$NAME"

# Same refusal rules as fetch.sh: only the verified tarball goes in.
while read -r name version url hash; do
    file=$DOWNLOADS/$name-$version/$(basename "${url%%\?*}")
    [[ -f "$file" ]] || { echo "error: $file missing; run make vendor-fetch" >&2; exit 1; }
    [[ "sha256:$(shasum -a 256 "$file" | cut -d' ' -f1)" == "$hash" ]] ||
        { echo "error: $file does not match its pinned SHA-256" >&2; exit 1; }
    mkdir -p "$WORK/$NAME/upstream/$name-$version"
    cp "$file" "$WORK/$NAME/upstream/$name-$version/"
done < <(awk '!/^[[:space:]]*(#|$)/' "$REPO_ROOT/Vendor/versions.lock")

# cargo vendor takes every platform's crates (also Linux-only ones), so it may download into CARGO_HOME; each crate
# is checked against Cargo.lock.
(cd "$REPO_ROOT/Vendor/rs/zivlet-svg" && CARGO_HOME=$CARGO_HOME cargo vendor --quiet --locked --versioned-dirs \
    "$WORK/$NAME/vendor" >/dev/null)

cat >"$WORK/$NAME/SOURCES.md" <<EOF
# Zivlet $VERSION: corresponding source

This archive holds everything needed to rebuild the third-party binaries bundled in Zivlet $VERSION.

| Directory | Contents |
|---|---|
| \`zivlet-$VERSION/\` | Zivlet's source at \`$(git -C "$REPO_ROOT" rev-parse "$REF")\` |
| \`upstream/\` | The unmodified upstream tarballs pinned in \`Vendor/versions.lock\` (SHA-256 listed there) |
| \`vendor/\` | The Rust crates of \`Vendor/rs/zivlet-svg\`, as resolved by its \`Cargo.lock\` |

To rebuild on an Apple-silicon Mac with Xcode and the tools named in \`README.md\`:

1. Copy the directories in \`upstream/\` into \`zivlet-$VERSION/Vendor/downloads/\` (\`Vendor/fetch.sh\` checks the
   hashes and skips the download).
2. Run \`make vendor\` in \`zivlet-$VERSION/\`: FFmpeg with its codec libraries, libwebp and the SVG renderer.
3. For the Rust crates without network access, point Cargo at \`vendor/\` (\`[source.crates-io] replace-with\`).
4. \`make app\` builds Zivlet with those binaries.
EOF

COPYFILE_DISABLE=1 tar -C "$WORK" -cJf "$RELEASE/$NAME.tar.xz" "$NAME"
echo "wrote $RELEASE/$NAME.tar.xz ($(du -h "$RELEASE/$NAME.tar.xz" | cut -f1 | tr -d ' '))"
