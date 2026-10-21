# 06f — M1 task 9: XcodeGen app target, dev entry points, M1 exit check

Part of [06-implementation-plan-m1](06-implementation-plan-m1.md). Conventions: index §4. Commands run from `$REPO`
with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the Makefile sets it if missing).

---

## Task 9 — XcodeGen app target and dev entry points

| Field | Value |
|---|---|
| Goal | `project.yml` generates `Zivlet.xcodeproj` (ignored) with a menu-bar agent app linking ZivletKit; `make test/coverage/lint/format/app` work on a clean clone |
| 05 rows | P0-04, P0-05, P0-06 (Sparkle, helper embedding and UI tests arrive with P1-50/P1-53) |
| Sources | 04 §3.1–3.5 (targets, build settings, Info.plist keys, entitlements), 04 §1.2 (`DEVELOPER_DIR`), 04 §6.8, 10 §11.2, O-10, O-11 |

**Files (repo root):** `project.yml`, `Config/Base.xcconfig`, `Config/Debug.xcconfig`, `Config/Release.xcconfig`,
`Config/Zivlet.entitlements`, `App/ZivletApp.swift`, `Scripts/env.sh`, `Scripts/coverage.sh`, `Makefile`.

### 9.1 Failing check first

Write `Scripts/env.sh` and `Makefile` first, then run `make app`.

```bash
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
```

```make
# Dev entry points (04 §1.3, 05 P0-05). Every target sources Scripts/env.sh.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
ENV := source Scripts/env.sh &&

.PHONY: test coverage lint format app

test:
	$(ENV) cd "$$KIT" && swift test

coverage:
	Scripts/coverage.sh

lint:
	$(ENV) swift format lint --strict --recursive Packages/ZivletKit/Sources Packages/ZivletKit/Tests App

format:
	$(ENV) swift format format --in-place --recursive Packages/ZivletKit/Sources Packages/ZivletKit/Tests App

app:
	$(ENV) /opt/homebrew/bin/xcodegen generate --spec project.yml && \
	xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Debug \
	  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- build 2>&1 | grep -v -e DVTPlugIn -e CoreSimulator -e CoreDevice
```

`.SHELLFLAGS` sets `pipefail`, so a failed `xcodebuild` fails `make app` even though its output goes through `grep`
(verified: a planted type error exits 2).

```bash
cd "$REPO" && chmod +x Scripts/env.sh && make app
```

Expected: `No project spec found at …/project.yml` and `make: *** [app] Error 1`.

### 9.2 Implement

`project.yml` (04 §3.5 minus Sparkle, helper embedding and UI tests, which arrive with the code that needs them):

```yaml
name: Zivlet
options:
  bundleIdPrefix: app.zivlet
  deploymentTarget:
    macOS: "26.0"
  xcodeVersion: "27.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
configFiles:
  Debug: Config/Debug.xcconfig
  Release: Config/Release.xcconfig
packages:
  ZivletKit:
    path: Packages/ZivletKit
targets:
  Zivlet:
    type: application
    platform: macOS
    sources: [App]
    dependencies:
      - package: ZivletKit
        product: ZivletKit
    info:
      path: App/Info.plist
      properties:
        CFBundleName: Zivlet
        CFBundleDisplayName: Zivlet
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSUIElement: true
        LSMinimumSystemVersion: "26.0"
        LSApplicationCategoryType: public.app-category.utilities
        NSHumanReadableCopyright: "Copyright © 2026 Zivlet contributors. GPL-3.0-or-later."
    entitlements:
      path: Config/Zivlet.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.zivlet.Zivlet
        SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
schemes:
  Zivlet:
    build:
      targets:
        Zivlet: all
```

`Config/Base.xcconfig`:

```text
// Shared by all configurations (04 §3.2).
MACOSX_DEPLOYMENT_TARGET = 26.0
ARCHS = arm64
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
GCC_TREAT_WARNINGS_AS_ERRORS = YES
ENABLE_HARDENED_RUNTIME = YES
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
GENERATE_INFOPLIST_FILE = NO
MARKETING_VERSION = 0.0.1
CURRENT_PROJECT_VERSION = 1
```

`Config/Debug.xcconfig`:

```text
#include "Base.xcconfig"
ONLY_ACTIVE_ARCH = YES
OTHER_CODE_SIGN_FLAGS = --options=runtime
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
```

`Config/Release.xcconfig`:

```text
#include "Base.xcconfig"
ONLY_ACTIVE_ARCH = NO
DEAD_CODE_STRIPPING = YES
STRIP_INSTALLED_PRODUCT = YES
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
```

`Config/Zivlet.entitlements` (empty: not sandboxed, no exceptions in Phase 0–1; 04 §3.4):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

`App/ZivletApp.swift` (composition root only; proves the package links):

```swift
import ZivletCore
import SwiftUI

/// Composition root only (04 §2). M1: a menu-bar agent that proves the package links.
@main
struct ZivletApp: App {
    var body: some Scene {
        MenuBarExtra("Zivlet", systemImage: "circle.hexagongrid") {
            Text(StatusSummary.text)
            Divider()
            Button("Quit Zivlet") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

enum StatusSummary {
    static var text: String {
        "\(ConversionCatalog.standard.pairs.count) conversions · \(ToolID.allCases.count) tools"
    }
}
```

`Scripts/coverage.sh` (index D13; reads every test bundle, gates each module at 80 %):

```bash
#!/usr/bin/env bash
# Line coverage per module over every test bundle; fails below the gate (owner rule: 80 %).
source "$(dirname "$0")/env.sh"
GATE="${COVERAGE_GATE:-80}"
GATED_MODULES="${GATED_MODULES:-ZivletCore ZivletTrigger ZivletWheelCore EngineMedia}"
cd "$KIT"
swift test --enable-code-coverage >/dev/null
BIN="$(swift build --show-bin-path)"
objects=()
for bundle in "$BIN"/*.xctest; do
    objects+=(-object "$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
done
report="$(xcrun llvm-cov report -instr-profile "$BIN/codecov/default.profdata" "${objects[@]}" \
    -ignore-filename-regex='(Tests|\.build)/')"
status=0
for module in $GATED_MODULES; do
    read -r covered total < <(awk -v m="$module/" '
        index($1, m) == 1 { total += $8; missed += $9 }
        END { print total - missed, total }' <<<"$report")
    pct=$(( total > 0 ? covered * 100 / total : 0 ))
    printf '%-18s %5d/%-5d lines  %3d%%\n' "$module" "$covered" "$total" "$pct"
    if (( pct < GATE )); then status=1; fi
done
exit $status
```

### 9.3 Verify green

```bash
cd "$REPO" && chmod +x Scripts/coverage.sh
make app
APP=build/DerivedData/Build/Products/Debug/Zivlet.app
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' -c 'Print :CFBundleIdentifier' -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|flags'
[ "$(git check-ignore Zivlet.xcodeproj App/Info.plist | wc -l)" -eq 2 ] && echo IGNORED
open "$APP"      # manual: menu-bar icon, no Dock icon, menu shows "275 conversions · 27 tools"; Quit with ⌘Q
```

| Check | Expected |
|---|---|
| `make app` | `** BUILD SUCCEEDED **` (Release also builds: add `-configuration Release`). [critic3] Xcode prints `note: Disabling hardened runtime with ad-hoc codesigning`; ignore it: `OTHER_CODE_SIGN_FLAGS = --options=runtime` still sets the runtime flag (codesign row) |
| Info.plist | `true`, `app.zivlet.Zivlet`, `26.0` |
| codesign | `Identifier=app.zivlet.Zivlet`, `flags=0x10002(adhoc,runtime)` |
| ignore | `IGNORED` |
| manual launch | no Dock icon; the menu-bar menu lists the catalog counts |

### 9.4 Commit

```bash
git add project.yml Config App/ZivletApp.swift Scripts Makefile
git commit -s -m "feat(app): add XcodeGen menu-bar app target, Makefile and coverage gate"
```

---

## M1 exit check (for the scope of this plan)

Run from a fresh clone so nothing generated is reused:

```bash
git clone "$REPO" /tmp/zivlet-m1-check && cd /tmp/zivlet-m1-check
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make test && make coverage && make lint && make app && git status --porcelain
```

| Step | Expected |
|---|---|
| `make test` | Five `✔ Test run with …` lines: 33 (Core), 29 (Trigger), 24 (WheelCore), 1 (EngineKit), 16 (EngineMedia) = 103 [critic3: re-run after index D4] |
| `make coverage` | Four rows, each ≥ 80 % (reference run: Core 98 %, Trigger 100 %, WheelCore 99 %, EngineMedia 95 %); exit 0 |
| `make lint` | no findings; exit 0 |
| `make app` | `** BUILD SUCCEEDED **` |
| `git status --porcelain` | empty (`Zivlet.xcodeproj`, `App/Info.plist`, `build/`, `.build/` are ignored) |

M1 as defined in 05 §2 also needs the rows in index §2.1 (P0-03, P0-07, P0-11, P0-13, P0-17…P0-20, P0-22,
P0-26…P0-28) and CI green on `main`. Plan them next; do not report M1 done before they pass.
