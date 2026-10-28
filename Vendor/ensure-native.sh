#!/usr/bin/env bash
# Builds the SwiftPM binary targets CWebP, CZivletSVG and CQPDF only when missing or stale (D-M4-9, D-M7-16). Run by
# make test, smoke, coverage, app and release-check before Swift sees Package.swift (about 1 min on a clean clone).
set -euo pipefail
exec "$(dirname "$0")/vendor.sh" CWebP CZivletSVG CQPDF
