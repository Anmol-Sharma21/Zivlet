#!/usr/bin/env bash
# m7-exit.sh runs the M7 exit rows V1–V13 (plan 20 §7, D-M7-26) in order, each into its own log, and prints one line
# per row. Here make, codesign, otool and the log reader are stand-ins on PATH, the Release app is a folder of small
# files and the Vendor folder a stand-in with its own verify scripts, so the test checks the runner: the row list,
# --only, the summary, a failing step, a locked-screen skip, a timing row not judged, the qpdf provenance row, the
# TCC rule of D-M5a-5 for the demos, and the hygiene row against small throwaway repositories.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/m7-exit.sh
listed=$("$SCRIPT" --list)
for row in V1 V2 V3 V4 V5 V6 V7 V8 V9 V10 V11 V12 V13; do assert_contains "$listed" "$row "; done
assert_eq "$(grep -c . <<<"$listed")" "13" "--list prints thirteen rows"
assert_contains "$listed" "make test lint coverage app release-check licence-gate"
assert_contains "$listed" "m6-exit.sh --only Z4,Z5,Z7,Z8"
for target in timing pdf-smoke password-policy lock-demo qr-demo locked-input-demo tool-states; do
    assert_contains "$listed" "make $target"
done
assert_contains "$listed" "Vendor/verify-native.sh CQPDF"
assert_eq "$("$SCRIPT" --list --only V12,V3 | cut -d' ' -f1 | tr '\n' ' ')" "V3 V12 " "--only keeps the row order"
assert_fails "$SCRIPT" --list --only V14
assert_fails "$SCRIPT" --only Z4
assert_fails "$SCRIPT" --bogus
for target in m7-exit password-policy; do
    grep -q "^$target:" "$ROOT/Makefile" || fail "Makefile has no $target target"
done

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
APP=$T/Release/Zivlet.app
WORKER_BINARY=$APP/Contents/XPCServices/ZivletWorker.xpc/Contents/MacOS/ZivletWorker
mkdir -p "$APP/Contents/MacOS" "$(dirname "$WORKER_BINARY")" "$APP/Contents/Resources/Licenses"
printf 'app code\n' >"$APP/Contents/MacOS/Zivlet"
printf 'worker code: unsupported encryption filter\n' >"$WORKER_BINARY"
for name in qpdf libjpeg-turbo; do printf 'licence of %s\n' "$name" >"$APP/Contents/Resources/Licenses/$name.txt"; done
# The Vendor stand-in: the two pins with tarballs that match them, and verify scripts that pass unless told not to.
VENDOR=$T/Vendor
: >"$T/versions.lock"
for entry in "qpdf 12.4.2 qpdf-12.4.2.tar.gz" "libjpeg-turbo 3.2.0 libjpeg-turbo-3.2.0.tar.gz"; do
    read -r name version file <<<"$entry"
    mkdir -p "$VENDOR/downloads/$name-$version"
    printf 'source of %s\n' "$name" >"$VENDOR/downloads/$name-$version/$file"
    hash=$(shasum -a 256 "$VENDOR/downloads/$name-$version/$file" | cut -d' ' -f1)
    echo "$name $version https://example.com/$file sha256:$hash" >>"$T/versions.lock"
done
cp "$T/versions.lock" "$VENDOR/versions.lock"
for tool in verify-sources verify-native; do
    printf '#!/usr/bin/env bash\n[[ "${FAKE_VERIFY_FAIL:-}" == %s ]] && { echo "%s: a problem"; exit 1; }\necho "%s ok $*"\n' \
        "$tool" "$tool" "$tool" >"$VENDOR/$tool.sh"
done
# make fails for the target named in FAKE_MAKE_FAIL and prints FAKE_MAKE_OUTPUT; `make timing` with FAKE_TIMING_BUSY
# says it did not judge and exits 3, as Scripts/timing.sh does; `make cap-lint COUNTS=<file>` writes one count line.
cat >"$T/bin/make" <<'EOF'
#!/usr/bin/env bash
[[ -n "${FAKE_MAKE_FAIL:-}" && " $* " == *" $FAKE_MAKE_FAIL "* ]] && exit 1
if [[ -n "${FAKE_TIMING_BUSY:-}" && " $* " == *" timing "* ]]; then echo "timing: not judged (load 1m 9.00 > 3.0)"; exit 3; fi
for arg; do [[ "$arg" == COUNTS=* ]] && echo "png single tools 9/12" >"${arg#COUNTS=}"; done
echo "$FAKE_MAKE_OUTPUT"
EOF
# codesign: the worker's identity and flags, and its entitlements (FAKE_ENTITLEMENTS) on stdout.
cat >"$T/bin/codesign" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --entitlements "* ]]; then printf '%s' "${FAKE_ENTITLEMENTS:-}"; exit 0; fi
printf 'Identifier=app.zivlet.Zivlet.Worker\nCodeDirectory v=20500 size=1 flags=0x10002(adhoc,runtime) hashes=1+3 location=embedded\n' >&2
EOF
printf '#!/usr/bin/env bash\necho "$1:"\necho "\t/usr/lib/libSystem.B.dylib"\n[[ -n "${FAKE_OTOOL:-}" ]] && echo "\t$FAKE_OTOOL"\nexit 0\n' \
    >"$T/bin/otool"
printf '#!/usr/bin/env bash\n[[ -n "${FAKE_LOG_FAIL:-}" && "$*" == *com.apple.TCC* ]] && exit 1\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' \
    >"$T/bin/fake-log"
printf '#!/usr/bin/env bash\necho "{ ${FAKE_LOAD:-1.00} 1.00 1.00 }"\n' >"$T/bin/fake-load"
chmod +x "$T/bin/"* "$VENDOR/"*.sh
touch "$T/srgb.heic"
signpost=$(printf '{"eventType":"signpostEvent","signpostName":"drop→island","signpostID":7,"signpostType":"%s","machTimestamp":%s}\n' \
    begin 1000000 end 1432000)
coverage=$(printf '%s\n' "EnginePDF          862/876   lines   98%" "CZivletPDF         471/512   lines   91%" \
    "Result card: <private> · 57 KB → 297 KB")
# V3 runs the real m5a-exit.sh, m5b-exit.sh and m6-exit.sh, which read the same stand-ins through their overrides.
run() {
    PATH=$T/bin:$PATH ZIVLET_M7_EXIT_LOGS=$T/logs ZIVLET_M7_LOG=$T/bin/fake-log ZIVLET_M7_RELEASE_APP=$APP \
        ZIVLET_M7_VENDOR=$VENDOR ZIVLET_M6_EXIT_LOGS=$T/m6-logs ZIVLET_M6_LOG=$T/bin/fake-log \
        ZIVLET_M6_RELEASE_APP=$APP ZIVLET_M5B_EXIT_LOGS=$T/m5b-logs ZIVLET_M5B_LOG=$T/bin/fake-log \
        ZIVLET_M5A_EXIT_LOGS=$T/m5a-logs ZIVLET_M5A_LOG=$T/bin/fake-log ZIVLET_M5A_FIXTURE=$T/srgb.heic \
        ZIVLET_LOADAVG=$T/bin/fake-load ZIVLET_PCORES=6 ZIVLET_TIMING_WAIT=0 ZIVLET_M5A_TICKS=24000000 \
        FAKE_MAKE_OUTPUT=${MAKE_OUTPUT:-$coverage} FAKE_LOG_OUTPUT=$1 "$SCRIPT" "${@:2}"
}
out=$(run "$signpost" --only V1,V2,V3,V4,V5,V6,V7,V8,V9,V10,V11,V12) || fail "every row stubbed to pass must pass: $out"
for row in V1 V2 V3 V4 V5 V6 V7 V8 V9 V10 V11 V12; do assert_contains "$out" "$row pass"; done
assert_contains "$(cat "$T/logs/V3.log")" "Z4 pass"
assert_contains "$(cat "$T/logs/V5.log")" "qpdf is in the worker only"
assert_contains "$(cat "$T/logs/V5.log")" "of 4.5 MB"
assert_contains "$(cat "$T/logs/V5.log")" "libjpeg-turbo 3.2.0: licence text in the bundle"
assert_contains "$(cat "$T/logs/V12.log")" "no tccd request with preflight=no"

# V1 needs a coverage line with a percentage for EnginePDF and the shim.
out=$(MAKE_OUTPUT="EnginePDF          862/876   lines   98%" run "$signpost" --only V1 || true)
assert_contains "$out" "V1 FAIL"
assert_contains "$(cat "$T/logs/V1.log")" "CZivletPDF"

# V4: not judged above the load limit is a skip with the load, and the run exits 1; a missed budget fails.
status=0; out=$(FAKE_TIMING_BUSY=1 run "$signpost" --only V4) || status=$?
assert_eq "$status" "1" "a timing row not judged fails the exit run"
assert_contains "$out" "V4 SKIP"
assert_contains "$out" "load 1m 9.00"
out=$(FAKE_MAKE_FAIL=timing run "$signpost" --only V4 || true)
assert_contains "$out" "V4 FAIL"

# V5: each part of the qpdf row fails it on its own.
for fault in verify-sources verify-native; do
    out=$(FAKE_VERIFY_FAIL=$fault run "$signpost" --only V5 || true)
    assert_contains "$out" "V5 FAIL"
done
out=$(FAKE_OTOOL="/opt/homebrew/lib/libcrypto.3.dylib" run "$signpost" --only V5 || true)
assert_contains "$out" "V5 FAIL"
assert_contains "$(cat "$T/logs/V5.log")" "links a crypto"
printf 'unsupported encryption filter\n' >>"$APP/Contents/MacOS/Zivlet"
out=$(run "$signpost" --only V5 || true)
assert_contains "$out" "V5 FAIL"
assert_contains "$(cat "$T/logs/V5.log")" "app's own binary has qpdf code"
printf 'app code\n' >"$APP/Contents/MacOS/Zivlet"
mv "$APP/Contents/Resources/Licenses/qpdf.txt" "$T/qpdf.txt"
out=$(run "$signpost" --only V5 || true)
assert_contains "$out" "V5 FAIL"
assert_contains "$(cat "$T/logs/V5.log")" "no licence text"
mv "$T/qpdf.txt" "$APP/Contents/Resources/Licenses/qpdf.txt"
sed 's/sha256:[0-9a-f]*$/sha256:0000/' "$T/versions.lock" >"$VENDOR/versions.lock"
out=$(run "$signpost" --only V5 || true)
assert_contains "$out" "V5 FAIL"
assert_contains "$(cat "$T/logs/V5.log")" "does not match its pinned SHA-256"
grep -v '^libjpeg-turbo' "$T/versions.lock" >"$VENDOR/versions.lock"
out=$(run "$signpost" --only V5 || true)
assert_contains "$(cat "$T/logs/V5.log")" "libjpeg-turbo is not pinned"
cp "$T/versions.lock" "$VENDOR/versions.lock"
dd if=/dev/zero of="$WORKER_BINARY" bs=1 count=0 seek=11000000 2>/dev/null
printf 'unsupported encryption filter\n' >>"$WORKER_BINARY"
out=$(run "$signpost" --only V5 || true)
assert_contains "$out" "V5 FAIL"
assert_contains "$(cat "$T/logs/V5.log")" "OS-M7-9"
printf 'worker code: unsupported encryption filter\n' >"$WORKER_BINARY"

# A failing demo fails its own row only; a screenshot row that found the screen locked is a skip, not a pass.
out=$(FAKE_MAKE_FAIL=lock-demo run "$signpost" --only V8,V9 || true)
assert_contains "$out" "V8 FAIL"
assert_contains "$out" "V9 pass"
status=0; out=$(MAKE_OUTPUT="skipped: screen locked" run "$signpost" --only V11) || status=$?
assert_contains "$out" "V11 SKIP"
assert_eq "$status" "1" "a skipped row exits 1"

# V12: a request that could prompt, for the app or its worker, fails; preflight checks are listed only.
asked="2026-11-07 10:00:02 tccd: AUTHREQ_SUBJECT: msgID=1, function=TCCAccessRequest, service=kTCCServiceSystemPolicyDownloadsFolder, preflight=no, subject=app.zivlet.Zivlet.Worker"
demos=V6,V7,V8,V9,V10,V11,V12
out=$(run "$(printf '%s\n%s' "$signpost" "$asked")" --only "$demos" || true)
assert_contains "$out" "V12 FAIL"
assert_contains "$(cat "$T/logs/V12.log")" "app.zivlet.Zivlet.Worker"
out=$(run "" --only "$demos" || true)
assert_contains "$(cat "$T/logs/V12.log")" "nothing to check"
out=$(run "$signpost" --only V6,V12 || true)
assert_contains "$out" "V12 FAIL"
assert_contains "$(cat "$T/logs/V12.log")" "needs V6, V7, V8, V9, V10 and V11"
out=$(FAKE_LOG_FAIL=1 run "$signpost" --only "$demos" || true)
assert_contains "$out" "V12 FAIL"

# V13 in a throwaway repository: the runner and what it sources in a base commit, then one commit per case.
GIT=(git -c user.name=Tester -c user.email=tester@example.com -c commit.gpgsign=false)
make_repo() {
    local repo=$1
    mkdir -p "$repo/Scripts" "$repo/Packages/ZivletKit/Sources/EngineVision" "$repo/Packages/ZivletKit/Sources/CZivletPDF" \
        "$repo/App" "$repo/Worker"
    cp "$ROOT/Scripts/m7-exit.sh" "$ROOT/Scripts/m7-exit-rows.sh" "$ROOT/Scripts/env.sh" "$ROOT/Scripts/exit-lib.sh" \
        "$repo/Scripts/"
    printf 'import Vision\n' >"$repo/Packages/ZivletKit/Sources/EngineVision/OCR.swift"
    printf '#include <qpdf/QPDF.hh>\n' >"$repo/Packages/ZivletKit/Sources/CZivletPDF/shim.cc"
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
    if [[ "$3" == @copy:* ]]; then cp "${3#@copy:}" "$repo/$2"; else printf '%s\n' "$3" >"$repo/$2"; fi
    "${GIT[@]}" -C "$repo" add -A
    "${GIT[@]}" -C "$repo" commit -q "${@:4}"
    PATH=$T/bin:$PATH ZIVLET_M7_EXIT_LOGS=$repo/logs ZIVLET_M7_BASE=$base ZIVLET_M7_RELEASE_APP=$APP \
        "$repo/Scripts/m7-exit.sh" --only V13 || true
}
v13_log() { cat "$T/repo-$1/logs/V13.log"; }
out=$(hygiene clean Notes.md "a note" -s -m "docs: a note")
assert_contains "$out" "V13 pass"
assert_contains "$(v13_log clean)" "png single tools 9/12"
out=$(hygiene unsigned Notes.md "a note" -m "docs: a note")
assert_contains "$out" "V13 FAIL"
assert_contains "$(v13_log unsigned)" "not signed off"
out=$(hygiene coauthor Notes.md "a note" -s -m "docs: a note" -m "Co-Authored-By: Someone <someone@example.com>")
assert_contains "$(v13_log coauthor)" "Co-Authored-By"
out=$(hygiene print App/Hello.swift 'print("hello")' -s -m "feat: hello")
assert_contains "$out" "V13 FAIL"
assert_contains "$(v13_log print)" "print("
out=$(hygiene keychain App/Store.swift 'let status = SecItemAdd(query, nil)' -s -m "feat: store")
assert_contains "$out" "V13 FAIL"
assert_contains "$(v13_log keychain)" "Keychain item API"
out=$(hygiene argv Worker/Run.swift 'let arguments = ["--password", typed]' -s -m "feat: run")
assert_contains "$(v13_log argv)" "a --password argument"
out=$(hygiene header Packages/ZivletKit/Sources/EnginePDF/bridge.h '#include <qpdf/QPDF.hh>' -s -m "feat: bridge")
assert_contains "$(v13_log header)" "qpdf headers outside CZivletPDF"
out=$(hygiene vision App/Scan.swift "import Vision" -s -m "feat: scan")
assert_contains "$(v13_log vision)" "import Vision outside EngineVision"
out=$(hygiene alert App/Ask.swift "let alert = NSAlert()" -s -m "feat: ask")
assert_contains "$(v13_log alert)" "NSAlert"
out=$(hygiene long Long.swift "$(seq 1 800 | sed 's/^/let x/')" -s -m "feat: long")
assert_contains "$(v13_log long)" "Long.swift has 800 lines"
out=$(hygiene personal Notes.md "see /Users/$(whoami)/notes" -s -m "docs: a path")
assert_contains "$(v13_log personal)" "personal path"
out=$(hygiene prior Notes.md "as Tangerine does" -s -m "docs: prior art")
assert_contains "$(v13_log prior)" "another app's name"
out=$(hygiene pdf Fixtures/sample.pdf "%PDF-1.7" -s -m "test: a sample")
assert_contains "$(v13_log pdf)" "a PDF file was added"
printf 'a\001\000b' >"$T/blob.bin"  # a NUL byte: git counts the file as binary
out=$(hygiene binary Fixtures/blob.bin "@copy:$T/blob.bin" -s -m "test: a blob")
assert_contains "$(v13_log binary)" "a binary file was added"
out=$(FAKE_ENTITLEMENTS='<dict><key>com.apple.security.app-sandbox</key><true/></dict>' \
    hygiene entitled Notes.md "a note" -s -m "docs: a note")
assert_contains "$(v13_log entitled)" "entitlements"
# An unknown base checks nothing, so it fails instead of passing vacuously.
make_repo "$T/repo-nobase"
out=$(PATH=$T/bin:$PATH ZIVLET_M7_EXIT_LOGS=$T/repo-nobase/logs ZIVLET_M7_BASE=0123abc ZIVLET_M7_RELEASE_APP=$APP \
    "$T/repo-nobase/Scripts/m7-exit.sh" --only V13 || true)
assert_contains "$out" "V13 FAIL"
assert_contains "$(cat "$T/repo-nobase/logs/V13.log")" "unknown base 0123abc"
echo "PASS test-m7-exit"
