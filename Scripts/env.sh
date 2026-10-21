#!/usr/bin/env bash
# Sourced by every script and make target (04 §1.2). Never runs xcode-select.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "error: Xcode not found at $DEVELOPER_DIR (set DEVELOPER_DIR)" >&2
    exit 1
fi
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
export KIT="$REPO_ROOT/Packages/ZivletKit"
