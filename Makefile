# Dev entry points (04 §1.3, 05 P0-05). Every target sources Scripts/env.sh.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
ENV := source Scripts/env.sh &&
# Builds the CWebP and CZivletSVG binary targets when missing or stale, before Swift reads Package.swift (D-M4-9).
NATIVE := Vendor/ensure-native.sh &&

.PHONY: test smoke coverage lint format app demo release-check convert-demo vendor-test vendor-fetch vendor-media vendor vendor-pack vendor-unpack script-test

test:
	$(ENV) $(NATIVE) cd "$$KIT" && swift test

# Opt-in: run planned argv through a real ffmpeg (ZIVLET_FFMPEG_DIR holds ffmpeg and ffprobe).
smoke:
	$(ENV) : "$${ZIVLET_FFMPEG_DIR:?set ZIVLET_FFMPEG_DIR to a directory with ffmpeg and ffprobe}" && \
	$(NATIVE) cd "$$KIT" && swift test --filter FFmpegSmokeTests

coverage:
	$(ENV) $(NATIVE) Scripts/coverage.sh

lint:
	$(ENV) swift format lint --strict --recursive Packages/ZivletKit/Sources Packages/ZivletKit/Tests App
	Scripts/check-log-privacy.sh

format:
	$(ENV) swift format format --in-place --recursive Packages/ZivletKit/Sources Packages/ZivletKit/Tests App

app:
	$(ENV) $(NATIVE) /opt/homebrew/bin/xcodegen generate --spec project.yml && \
	xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Debug \
	  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- build 2>&1 | grep -v -e DVTPlugIn -e CoreSimulator -e CoreDevice

# Debug only: wheel at screen centre without a drag, screenshot in build/ (MODE=convert|tools|actions THEME=glass|solid).
demo:
	Scripts/demo-wheel.sh "$${MODE:-convert}" "$${THEME:-glass}"

# Debug only: one conversion through the drop path without a drag (FILE=/abs/in.ext TO=png [CANCEL_MS=300]).
convert-demo:
	Scripts/demo-convert.sh "$${FILE:?set FILE to an absolute input path}" "$${TO:?set TO to a target format}" "$${CANCEL_MS:-}"

# P1-21, P1-50: build Release with the vendored helpers; fail on a Homebrew path or an incomplete bundle.
release-check:
	$(ENV) $(NATIVE) Vendor/ensure-media.sh && Scripts/check-release-paths.sh

# Vendored sources and builds (10a). vendor-test runs every script test; vendor-fetch downloads and verifies sources.
vendor-test:
	@for t in Vendor/tests/test-*.sh; do bash "$$t" || exit 1; done

vendor-fetch:
	Vendor/fetch.sh

# Builds FFmpeg and the codec libraries from the fetched sources (about 3 minutes clean; does not fetch).
vendor-media:
	$(ENV) Vendor/build-media.sh

# Every vendor output (media stage, CWebP, CZivletSVG), rebuilding only what is missing or stale (cache key).
vendor:
	$(ENV) Vendor/vendor.sh

vendor-pack:
	$(ENV) Vendor/pack.sh

# Restores a packed vendor tree: make vendor-unpack TARBALL=Vendor/out/zivlet-vendor-<key>.tar.xz
vendor-unpack:
	$(ENV) Vendor/unpack.sh "$${TARBALL:?set TARBALL to a zivlet-vendor-<key>.tar.xz}"

# Shell tests of the release and bundle scripts (some need make vendor and make app first).
script-test:
	@for t in Scripts/tests/test-*.sh; do bash "$$t" || exit 1; done
