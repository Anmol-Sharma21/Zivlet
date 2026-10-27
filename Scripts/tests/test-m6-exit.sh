#!/usr/bin/env bash
# m6-exit.sh runs the M6 exit rows Z1–Z11 (plan 18 §7) in order, each into its own log, and prints one line per row.
# Here make, codesign and the log reader are stand-ins on PATH and the Release worker is an empty folder, so the test
# checks the runner: the row list, --only, the summary, a failing step, a locked-screen skip, the TCC rule of
# D-M5a-5 for the worker and Copy Text demos, the Release worker's signature, and the hygiene row against small
# throwaway repositories.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/m6-exit.sh
listed=$("$SCRIPT" --list)
for row in Z1 Z2 Z3 Z4 Z5 Z6 Z7 Z8 Z9 Z10 Z11; do assert_contains "$listed" "$row "; done
assert_eq "$(grep -c . <<<"$listed")" "11" "--list prints eleven rows"
assert_contains "$listed" "make test lint coverage app release-check licence-gate"
assert_contains "$listed" "make script-test"
assert_contains "$listed" "m5a-exit.sh --only X2,X3,X4,X5"
assert_contains "$listed" "m5b-exit.sh --only Y4,Y5,Y7"
assert_contains "$listed" "make worker-smoke"
assert_contains "$listed" "make ocr-check"
assert_contains "$listed" "make copy-text-demo"
assert_contains "$listed" "make box-busy-demo"
assert_contains "$listed" "make text-states"
assert_eq "$("$SCRIPT" --list --only Z10,Z3 | cut -d' ' -f1 | tr '\n' ' ')" "Z3 Z10 " "--only keeps the row order"
assert_fails "$SCRIPT" --list --only Z12
assert_fails "$SCRIPT" --only Y4
assert_fails "$SCRIPT" --bogus
for target in m6-exit cap-lint; do
    grep -q "^$target:" "$ROOT/Makefile" || fail "Makefile has no $target target"
done

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/Release/Zivlet.app/Contents/XPCServices/ZivletWorker.xpc"
# make fails for the target named in FAKE_MAKE_FAIL and prints FAKE_MAKE_OUTPUT; `make cap-lint COUNTS=<file>`
# writes one count line there. The log reader fails for the TCC stream when FAKE_LOG_FAIL is set.
cat >"$T/bin/make" <<'EOF'
#!/usr/bin/env bash
[[ -n "${FAKE_MAKE_FAIL:-}" && " $* " == *" $FAKE_MAKE_FAIL "* ]] && exit 1
for arg; do [[ "$arg" == COUNTS=* ]] && echo "png single tools 9/12" >"${arg#COUNTS=}"; done
echo "$FAKE_MAKE_OUTPUT"
EOF
# codesign: the worker's identity and flags (FAKE_FLAGS), and its entitlements (FAKE_ENTITLEMENTS) on stdout.
cat >"$T/bin/codesign" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --entitlements "* ]]; then printf '%s' "${FAKE_ENTITLEMENTS:-}"; exit 0; fi
printf 'Identifier=%s\nCodeDirectory v=20500 size=1 flags=%s hashes=1+3 location=embedded\n' \
    "${FAKE_IDENTIFIER:-app.zivlet.Zivlet.Worker}" "${FAKE_FLAGS:-0x10002(adhoc,runtime)}" >&2
EOF
printf '#!/usr/bin/env bash\n[[ -n "${FAKE_LOG_FAIL:-}" && "$*" == *com.apple.TCC* ]] && exit 1\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' \
    >"$T/bin/fake-log"
chmod +x "$T/bin/"*
touch "$T/srgb.heic"
signpost="2026-10-27 10:00:01 Zivlet: [app.zivlet.Zivlet:hud] drop→island end"
coverage=$(printf '%s\n' "ZivletIPC        900/1000  lines   90%" "ZivletWorkerCore  850/1000  lines   85%" \
    "EngineVision      820/1000  lines   82%" "Result card: <private> · 57 KB → 297 KB")
# Z3 runs the real m5a-exit.sh and m5b-exit.sh, which read the same stand-ins through their own overrides.
run() {
    PATH=$T/bin:$PATH ZIVLET_M6_EXIT_LOGS=$T/logs ZIVLET_M6_LOG=$T/bin/fake-log \
        ZIVLET_M6_RELEASE_APP=$T/Release/Zivlet.app \
        ZIVLET_M5B_EXIT_LOGS=$T/m5b-logs ZIVLET_M5B_LOG=$T/bin/fake-log \
        ZIVLET_M5A_EXIT_LOGS=$T/m5a-logs ZIVLET_M5A_LOG=$T/bin/fake-log ZIVLET_M5A_FIXTURE=$T/srgb.heic \
        FAKE_MAKE_OUTPUT=${MAKE_OUTPUT:-$coverage} FAKE_LOG_OUTPUT=$1 "$SCRIPT" "${@:2}"
}
out=$(run "$signpost" --only Z1,Z2,Z3,Z4,Z5,Z6,Z7,Z8,Z9,Z10) || fail "every row stubbed to pass must pass: $out"
for row in Z1 Z2 Z3 Z4 Z5 Z6 Z7 Z8 Z9 Z10; do assert_contains "$out" "$row pass"; done
assert_file "$T/logs/Z3.log"
assert_contains "$(cat "$T/logs/Z4.log")" "app.zivlet.Zivlet.Worker"
assert_contains "$(cat "$T/logs/Z10.log")" "no tccd request with preflight=no"

# Z1 needs a coverage line with a percentage for every new module: a module without lines is not a pass.
out=$(MAKE_OUTPUT="ZivletIPC        900/1000  lines   90%" run "$signpost" --only Z1 || true)
assert_contains "$out" "Z1 FAIL"
assert_contains "$(cat "$T/logs/Z1.log")" "ZivletWorkerCore"

# A failing step fails its own row only, and the run exits 1.
out=$(FAKE_MAKE_FAIL=worker-smoke run "$signpost" --only Z5,Z6,Z7 || true)
assert_contains "$out" "Z5 FAIL"
assert_contains "$out" "Z6 pass"
assert_contains "$out" "Z7 pass"
status=0; FAKE_MAKE_FAIL=box-busy-demo run "$signpost" --only Z8 >/dev/null || status=$?
assert_eq "$status" "1" "a failed row exits 1"

# A screenshot row whose script skipped because the screen was locked is not a pass, and the run is incomplete.
status=0
out=$(MAKE_OUTPUT="skipped: screen locked" run "$signpost" --only Z9) || status=$?
assert_contains "$out" "Z9 SKIP"
assert_contains "$out" "skipped: screen locked"
assert_eq "$status" "1" "a skipped row exits 1"

# Z4: the Release worker must exist, carry the hardened runtime and its identifier, and have no entitlements.
out=$(FAKE_FLAGS="0x2(adhoc)" run "$signpost" --only Z4 || true)
assert_contains "$out" "Z4 FAIL"
assert_contains "$(cat "$T/logs/Z4.log")" "hardened runtime"
out=$(FAKE_IDENTIFIER=app.zivlet.Other run "$signpost" --only Z4 || true)
assert_contains "$out" "Z4 FAIL"
out=$(FAKE_ENTITLEMENTS='<plist><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>' \
    run "$signpost" --only Z4 || true)
assert_contains "$out" "Z4 FAIL"
assert_contains "$(cat "$T/logs/Z4.log")" "entitlements"
mv "$T/Release" "$T/Release-away"
out=$(run "$signpost" --only Z4 || true)
assert_contains "$out" "Z4 FAIL"
mv "$T/Release-away" "$T/Release"

# Z10: a request that could prompt, for the app or its worker, fails; preflight checks are listed only.
asked="2026-10-27 10:00:02 tccd: AUTHREQ_SUBJECT: msgID=1, function=TCCAccessRequest, service=kTCCServiceSystemPolicyDownloadsFolder, preflight=no, subject=app.zivlet.Zivlet.Worker"
demos=Z5,Z6,Z7,Z8,Z9,Z10
out=$(run "$(printf '%s\n%s' "$signpost" "$asked")" --only "$demos" || true)
assert_contains "$out" "Z10 FAIL"
assert_contains "$(cat "$T/logs/Z10.log")" "app.zivlet.Zivlet.Worker"
checked="2026-10-27 10:00:03 tccd: AUTHREQ_SUBJECT: msgID=2, function=TCCAccessPreflight, service=kTCCServiceSystemPolicyDownloadsFolder, preflight=yes, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$checked")" --only "$demos") || fail "preflight checks must not fail Z10: $out"
assert_contains "$(cat "$T/logs/Z10.log")" "preflight=yes"
out=$(run "" --only "$demos" || true)
assert_contains "$out" "Z10 FAIL"
assert_contains "$(cat "$T/logs/Z10.log")" "nothing to check"
out=$(run "$signpost" --only Z5,Z6,Z10 || true)
assert_contains "$out" "Z10 FAIL"
assert_contains "$(cat "$T/logs/Z10.log")" "needs Z5, Z6, Z7, Z8 and Z9"
out=$(FAKE_LOG_FAIL=1 run "$signpost" --only "$demos" || true)
assert_contains "$out" "Z10 FAIL"

# Z11 in a throwaway repository: the runner and env.sh in a base commit, then one commit per case.
GIT=(git -c user.name=Tester -c user.email=tester@example.com -c commit.gpgsign=false)
make_repo() {
    local repo=$1
    mkdir -p "$repo/Scripts" "$repo/Packages/ZivletKit/Sources/EngineVision" "$repo/App" "$repo/Worker"
    cp "$ROOT/Scripts/m6-exit.sh" "$ROOT/Scripts/env.sh" "$repo/Scripts/"
    printf 'import Vision\n' >"$repo/Packages/ZivletKit/Sources/EngineVision/OCR.swift"
    printf 'let fingerprint = hash(of: data)\n' >"$repo/App/Hash.swift"
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
    PATH=$T/bin:$PATH ZIVLET_M6_EXIT_LOGS=$repo/logs ZIVLET_M6_BASE=$base \
        ZIVLET_M6_RELEASE_APP=$T/Release/Zivlet.app "$repo/Scripts/m6-exit.sh" --only Z11 || true
}
out=$(hygiene clean Notes.md "a note" -s -m "docs: a note")
assert_contains "$out" "Z11 pass"
assert_contains "$(cat "$T/repo-clean/logs/Z11.log")" "png single tools 9/12"
out=$(hygiene unsigned Notes.md "a note" -m "docs: a note")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-unsigned/logs/Z11.log")" "not signed off"
out=$(hygiene coauthor Notes.md "a note" -s -m "docs: a note" -m "Co-Authored-By: Someone <someone@example.com>")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-coauthor/logs/Z11.log")" "Co-Authored-By"
out=$(hygiene long Long.swift "$(seq 1 800 | sed 's/^/let x/')" -s -m "feat: long")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-long/logs/Z11.log")" "Long.swift has 800 lines"
out=$(hygiene personal Notes.md "see /Users/$(whoami)/notes" -s -m "docs: a path")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-personal/logs/Z11.log")" "personal path"
out=$(hygiene print Worker/main.swift 'print("hello")' -s -m "feat: hello")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-print/logs/Z11.log")" "print("
out=$(hygiene vision Packages/ZivletKit/Sources/ZivletUI/Scan.swift "import Vision" -s -m "feat: scan")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-vision/logs/Z11.log")" "ZivletUI/Scan.swift"
out=$(hygiene alert App/Ask.swift "let alert = NSAlert()" -s -m "feat: ask")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-alert/logs/Z11.log")" "NSAlert"
out=$(FAKE_ENTITLEMENTS='<dict><key>com.apple.security.app-sandbox</key><true/></dict>' \
    hygiene entitled Notes.md "a note" -s -m "docs: a note")
assert_contains "$out" "Z11 FAIL"
assert_contains "$(cat "$T/repo-entitled/logs/Z11.log")" "entitlements"
echo "PASS test-m6-exit"
