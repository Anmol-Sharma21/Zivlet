#!/usr/bin/env bash
# m5b-exit.sh runs the M5b exit rows Y1–Y9 (plan 16 §7) in order, each into its own log, and prints one line per
# row. Here make and the log reader are stand-ins on PATH, so the test checks the runner: the row list, --only, the
# summary, a failing step, the TCC rule of D-M5a-5 for the box demos, and the hygiene row against small throwaway
# repositories.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
listed=$("$ROOT/Scripts/m5b-exit.sh" --list)
for row in Y1 Y2 Y3 Y4 Y5 Y6 Y7 Y8 Y9; do assert_contains "$listed" "$row "; done
assert_eq "$(grep -c . <<<"$listed")" "9" "--list prints nine rows"
assert_contains "$listed" "make test lint coverage app release-check licence-gate"
assert_contains "$listed" "m5a-exit.sh --only X2,X3,X4,X5"
assert_contains "$listed" "make box-demo"
assert_contains "$listed" "make box-states"
assert_contains "$listed" "make drag-replay"
assert_contains "$listed" "make box-idle"
assert_eq "$("$ROOT/Scripts/m5b-exit.sh" --list --only Y6,Y3 | cut -d' ' -f1 | tr '\n' ' ')" "Y3 Y6 " "--only keeps the row order"
assert_fails "$ROOT/Scripts/m5b-exit.sh" --list --only Y10
assert_fails "$ROOT/Scripts/m5b-exit.sh" --only X2
assert_fails "$ROOT/Scripts/m5b-exit.sh" --bogus
grep -q '^m5b-exit:' "$ROOT/Makefile" || fail "Makefile has no m5b-exit target"

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
# make fails for the target named in FAKE_MAKE_FAIL; the log reader fails for the TCC stream when FAKE_LOG_FAIL is set.
printf '#!/usr/bin/env bash\n[[ -n "${FAKE_MAKE_FAIL:-}" && " $* " == *" $FAKE_MAKE_FAIL "* ]] && exit 1\necho "$FAKE_MAKE_OUTPUT"\n' \
    >"$T/bin/make"
printf '#!/usr/bin/env bash\n[[ -n "${FAKE_LOG_FAIL:-}" && "$*" == *com.apple.TCC* ]] && exit 1\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' \
    >"$T/bin/fake-log"
chmod +x "$T/bin/make" "$T/bin/fake-log"
touch "$T/srgb.heic"
signpost="2026-10-26 10:00:01 Zivlet: [app.zivlet.Zivlet:hud] drop→island end"
coverage=$(printf '%s\n%s\n%s' "ZivletShelfCore     900/1000  lines   90%" "ZivletBox          1700/2000  lines   85%" \
    "Result card: <private> · 57 KB → 297 KB")
# Y3 runs the real m5a-exit.sh, which reads the same stand-ins through its own overrides.
run() {
    PATH=$T/bin:$PATH ZIVLET_M5B_EXIT_LOGS=$T/logs ZIVLET_M5B_LOG=$T/bin/fake-log \
        ZIVLET_M5A_EXIT_LOGS=$T/m5a-logs ZIVLET_M5A_LOG=$T/bin/fake-log ZIVLET_M5A_FIXTURE=$T/srgb.heic \
        FAKE_MAKE_OUTPUT=${MAKE_OUTPUT:-$coverage} FAKE_LOG_OUTPUT=$1 "$ROOT/Scripts/m5b-exit.sh" "${@:2}"
}
out=$(run "$signpost" --only Y1,Y2,Y3,Y4,Y5,Y6,Y7,Y8) || fail "every row stubbed to pass must pass: $out"
for row in Y1 Y2 Y3 Y4 Y5 Y6 Y7 Y8; do assert_contains "$out" "$row pass"; done
assert_file "$T/logs/Y6.log"
assert_file "$T/logs/Y3.log"

# Y1 needs a coverage line with a percentage for both new modules: a module without lines is not a pass.
out=$(MAKE_OUTPUT="ZivletShelfCore     900/1000  lines   90%" run "$signpost" --only Y1 || true)
assert_contains "$out" "Y1 FAIL"
assert_contains "$(cat "$T/logs/Y1.log")" "ZivletBox"

# A failing step fails its own row only.
out=$(FAKE_MAKE_FAIL=box-demo run "$signpost" --only Y4,Y5,Y7 || true)
assert_contains "$out" "Y4 FAIL"
assert_contains "$out" "Y5 pass"
assert_contains "$out" "Y7 pass"
status=0; FAKE_MAKE_FAIL=box-demo run "$signpost" --only Y4 >/dev/null || status=$?
assert_eq "$status" "1" "a failed row exits 1"

# A screenshot row whose script skipped because the screen was locked is not a pass, and the run is incomplete.
status=0
out=$(MAKE_OUTPUT="skipped: screen locked" run "$signpost" --only Y5) || status=$?
assert_contains "$out" "Y5 SKIP"
assert_eq "$status" "1" "a skipped row exits 1"

asked="2026-10-26 10:00:02 tccd: AUTHREQ_SUBJECT: msgID=1, function=TCCAccessRequest, service=kTCCServiceSystemPolicyDownloadsFolder, preflight=no, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$asked")" --only Y3,Y4,Y5,Y6 || true)
assert_contains "$out" "Y6 FAIL"
assert_contains "$(cat "$T/logs/Y6.log")" "kTCCServiceSystemPolicyDownloadsFolder"

checked="2026-10-26 10:00:03 tccd: AUTHREQ_SUBJECT: msgID=2, function=TCCAccessPreflight, service=kTCCServiceSystemPolicyDownloadsFolder, preflight=yes, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$checked")" --only Y3,Y4,Y5,Y6) || fail "preflight checks must not fail Y6: $out"
assert_contains "$out" "Y6 pass"
assert_contains "$(cat "$T/logs/Y6.log")" "preflight=yes"

# An empty TCC stream is not "no request": the row fails and says why.
out=$(run "" --only Y3,Y4,Y5,Y6 || true)
assert_contains "$out" "Y6 FAIL"
assert_contains "$(cat "$T/logs/Y6.log")" "nothing to check"

# Y6 checks nothing on its own: the demos it watches must run in the same invocation.
out=$(run "$signpost" --only Y6 || true)
assert_contains "$out" "Y6 FAIL"
assert_contains "$(cat "$T/logs/Y6.log")" "needs Y3, Y4 and Y5"
out=$(run "$signpost" --only Y4,Y5,Y6 || true)
assert_contains "$out" "Y6 FAIL"
out=$(FAKE_LOG_FAIL=1 run "$signpost" --only Y3,Y4,Y5,Y6 || true)
assert_contains "$out" "Y6 FAIL"

# Y9 in a throwaway repository: the runner and env.sh in a base commit, then one commit per case.
GIT=(git -c user.name=Tester -c user.email=tester@example.com -c commit.gpgsign=false)
make_repo() {
    local repo=$1
    mkdir -p "$repo/Scripts" "$repo/Packages/ZivletKit/Sources/ZivletShelfCore" "$repo/Packages/ZivletKit/Sources/ZivletBox"
    cp "$ROOT/Scripts/m5b-exit.sh" "$ROOT/Scripts/env.sh" "$repo/Scripts/"
    printf 'import Foundation\nimport os\nimport ZivletCore\n' >"$repo/Packages/ZivletKit/Sources/ZivletShelfCore/Item.swift"
    printf 'import AppKit\n' >"$repo/Packages/ZivletKit/Sources/ZivletBox/Panel.swift"
    "${GIT[@]}" -C "$repo" init -q
    "${GIT[@]}" -C "$repo" add -A
    "${GIT[@]}" -C "$repo" commit -q -s -m "chore: base"
}
# $1 case name, $2 file to write (relative), $3 its content, then commit flags and the message.
hygiene() {
    local repo=$T/repo-$1 base
    make_repo "$repo"
    base=$("${GIT[@]}" -C "$repo" rev-parse HEAD)
    mkdir -p "$(dirname "$repo/$2")"
    printf '%s\n' "$3" >"$repo/$2"
    "${GIT[@]}" -C "$repo" add -A
    "${GIT[@]}" -C "$repo" commit -q "${@:4}"
    ZIVLET_M5B_EXIT_LOGS=$repo/logs ZIVLET_M5B_BASE=$base "$repo/Scripts/m5b-exit.sh" --only Y9 || true
}
out=$(hygiene clean Notes.md "a note" -s -m "docs: a note")
assert_contains "$out" "Y9 pass"
out=$(hygiene unsigned Notes.md "a note" -m "docs: a note")
assert_contains "$out" "Y9 FAIL"
assert_contains "$(cat "$T/repo-unsigned/logs/Y9.log")" "not signed off"
out=$(hygiene coauthor Notes.md "a note" -s -m "docs: a note" -m "Co-Authored-By: Someone <someone@example.com>")
assert_contains "$out" "Y9 FAIL"
assert_contains "$(cat "$T/repo-coauthor/logs/Y9.log")" "Co-Authored-By"
out=$(hygiene long Long.swift "$(seq 1 800 | sed 's/^/let x/')" -s -m "feat: long")
assert_contains "$out" "Y9 FAIL"
assert_contains "$(cat "$T/repo-long/logs/Y9.log")" "Long.swift has 800 lines"
out=$(hygiene personal Notes.md "see /Users/$(whoami)/notes" -s -m "docs: a path")
assert_contains "$out" "Y9 FAIL"
assert_contains "$(cat "$T/repo-personal/logs/Y9.log")" "personal path"
out=$(hygiene shelf Packages/ZivletKit/Sources/ZivletShelfCore/View.swift "import AppKit" -s -m "feat: a view")
assert_contains "$out" "Y9 FAIL"
assert_contains "$(cat "$T/repo-shelf/logs/Y9.log")" "import AppKit"
out=$(hygiene alert Packages/ZivletKit/Sources/ZivletBox/Ask.swift "let alert = NSAlert()" -s -m "feat: ask")
assert_contains "$out" "Y9 FAIL"
assert_contains "$(cat "$T/repo-alert/logs/Y9.log")" "NSAlert"
echo "PASS test-m5b-exit"
