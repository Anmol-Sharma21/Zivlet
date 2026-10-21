#!/usr/bin/env bash
# Builds the SwiftPM binary targets CWebP and CZivletSVG only when missing or stale (D-M4-9). Run by make test,
# smoke, coverage, app and release-check before Swift sees Package.swift (about 25 s on a clean clone).
set -euo pipefail
exec "$(dirname "$0")/vendor.sh" CWebP CZivletSVG
