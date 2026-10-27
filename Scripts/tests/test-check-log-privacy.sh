#!/usr/bin/env bash
# check-log-privacy.sh refuses public error descriptions and log categories outside the Phase 1 list (P1-48).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/Scripts" "$T/App" "$T/Packages/ZivletKit/Sources/M"
cp "$ROOT/Scripts/check-log-privacy.sh" "$T/Scripts/"
good='let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "media")'
printf '%s\n' "$good" >"$T/App/A.swift"
"$T/Scripts/check-log-privacy.sh" >/dev/null || fail "an allowed category was refused"
printf '%s\n' 'let s = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "telemetry")' >"$T/Packages/ZivletKit/Sources/M/B.swift"
out=$("$T/Scripts/check-log-privacy.sh" 2>&1 || true)
assert_contains "$out" 'log category "telemetry"'
assert_fails "$T/Scripts/check-log-privacy.sh"
printf '%s\n' "$good" >"$T/Packages/ZivletKit/Sources/M/B.swift"
printf '%s\n' 'logger.error("\(error.localizedDescription, privacy: .public)")' >>"$T/App/A.swift"
assert_fails "$T/Scripts/check-log-privacy.sh"
printf '%s\n' "$good" >"$T/App/A.swift"
"$T/Scripts/check-log-privacy.sh" >/dev/null || fail "a clean tree was refused"
# Plan 18d D14: recognised text is never logged, at any privacy level.
printf '%s\n' 'logger.notice("Copied \(outcome.fullText, privacy: .private)")' >>"$T/App/A.swift"
out=$("$T/Scripts/check-log-privacy.sh" 2>&1 || true)
assert_contains "$out" "recognised text is logged"
printf '%s\n' "$good" >"$T/App/A.swift"
printf '%s\n' 'logger.debug("Read \(recognized.text)")' >>"$T/App/A.swift"
assert_fails "$T/Scripts/check-log-privacy.sh"
printf '%s\n' "$good" >"$T/App/A.swift"
printf '%s\n' 'logger.notice("Copy Text finished: \(count) characters")' >>"$T/App/A.swift"
"$T/Scripts/check-log-privacy.sh" >/dev/null || fail "a count was refused"
"$ROOT/Scripts/check-log-privacy.sh" || fail "the repository itself fails the check"
echo "PASS test-check-log-privacy"
