#!/usr/bin/env bash
# Sourced by Scripts/m7-exit.sh: one function per exit row (plan 20 §7). Each runs inside its own bash process with
# errexit on, so any failing step fails its row; the runner reads the log for a skip line.

# V1: the gates, and a measured coverage line for each new module (coverage.sh passes a module without lines).
gates() {
    local out module
    make test lint
    out=$(make coverage)
    echo "$out"
    for module in $NEW_MODULES; do
        grep -Eq "^$module +[0-9]+/[0-9]+ +lines +[0-9]+%" <<<"$out" ||
            { echo "no coverage line with a percentage for $module"; return 1; }
    done
    make app release-check licence-gate
}

# V4: make timing passes when every budget was judged and met; "not judged" (exit 3, the load printed by timing.sh)
# leaves its line in the log, which the runner reports as a skip.
timing() {
    local out
    if out=$(make timing 2>&1); then
        echo "$out"
        return 0
    fi
    echo "$out"
    grep -qF "$NOT_JUDGED_LINE" <<<"$out" || return 1
    echo "the budgets were not judged (the load is in the line above)"
}

# The worker's entitlements as codesign prints them; any key is one too many (02 §2.1: the worker has no entitlements).
worker_entitlements_empty() {
    local entitlements
    [[ -d "$WORKER" ]] || { echo "no Release worker at $WORKER (make release-check builds it)"; return 1; }
    entitlements=$(codesign -d --entitlements - --xml "$WORKER" 2>/dev/null)
    if grep -q '<key>' <<<"$entitlements"; then
        echo "the worker has entitlements: $entitlements"
        return 1
    fi
    echo "the worker has no entitlements"
}

# V5, part 1: the Release worker links no crypto, TLS or qpdf library (all static, native crypto), qpdf's code is
# in the worker, and none of it is in the app's own binary.
qpdf_placement() {
    local worker_binary=$WORKER/Contents/MacOS/ZivletWorker app_binary=$RELEASE_APP/Contents/MacOS/Zivlet linked
    [[ -f "$worker_binary" && -f "$app_binary" ]] || { echo "no Release app or worker at $RELEASE_APP"; return 1; }
    linked=$(otool -L "$worker_binary")
    echo "$linked"
    if grep -iE 'libcrypto|libssl|gnutls|qpdf|libjpeg' <<<"$linked"; then
        echo "the worker links a crypto, TLS, qpdf or JPEG library (qpdf is static with native crypto)"
        return 1
    fi
    LC_ALL=C grep -qaF -- "$QPDF_MARKER" "$worker_binary" || { echo "the worker has no qpdf code"; return 1; }
    if LC_ALL=C grep -qaF -- "$QPDF_MARKER" "$app_binary"; then
        echo "the app's own binary has qpdf code (it belongs only in the worker)"
        return 1
    fi
    echo "qpdf is in the worker only; the worker links no crypto library"
}

# V5, part 2: qpdf's and libjpeg-turbo's licence texts in the bundle, and both pinned tarballs present with their
# hashes, as Scripts/source-bundle.sh copies every tarball of versions.lock into the corresponding source.
qpdf_texts_and_sources() {
    local name text line version url hash file status=0
    for name in qpdf libjpeg-turbo; do
        text=$RELEASE_APP/Contents/Resources/Licenses/$name.txt
        [[ -s "$text" ]] || { echo "no licence text $text"; status=1; }
        line=$(awk -v n="$name" '$1 == n' "$VENDOR/versions.lock")
        [[ -n "$line" ]] || { echo "$name is not pinned in versions.lock"; status=1; continue; }
        read -r _ version url hash <<<"$line"
        file=$VENDOR/downloads/$name-$version/$(basename "${url%%\?*}")
        if [[ ! -f "$file" ]]; then
            echo "the $name tarball is missing: the source bundle could not include it"
            status=1
        elif [[ "sha256:$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$hash" ]]; then
            echo "the $name tarball does not match its pinned SHA-256"
            status=1
        else
            echo "$name $version: licence text in the bundle, tarball pinned and present"
        fi
    done
    return "$status"
}

# V5, part 3: the worker's growth since it had no qpdf, against 10 §9's 4.5 MB (OS-M7-9 when over).
qpdf_size() {
    local bytes grown
    bytes=$(stat -f %z "$WORKER/Contents/MacOS/ZivletWorker")
    grown=$((bytes - WORKER_BYTES_WITHOUT_QPDF))
    awk -v b="$bytes" -v g="$grown" -v l="$QPDF_BUDGET_BYTES" 'BEGIN {
        printf "the Release worker is %.2f MB; qpdf, libjpeg-turbo and the worker code since add at most %.2f MB of %.1f MB\n",
            b / 1e6, g / 1e6, l / 1e6 }'
    ((grown <= QPDF_BUDGET_BYTES)) || { echo "over the 4.5 MB budget (owner step OS-M7-9)"; return 1; }
}

# V5: the provenance and build of qpdf. release-check already ran when V1 passed in this run; otherwise this row
# runs it.
qpdf_provenance() {
    local status=0
    "$VENDOR/verify-sources.sh"
    "$VENDOR/verify-native.sh" CQPDF
    echo "CQPDF: arm64 only, minos 26.0, no OpenSSL or GnuTLS, native crypto, no build paths"
    if [[ "${V1_PASSED:-}" == 1 ]]; then echo "release-check ran in V1"; else make release-check; fi
    qpdf_placement || status=1
    qpdf_texts_and_sources || status=1
    qpdf_size || status=1
    return "$status"
}

# V7: the policy suite and the source grep.
password_policy() {
    make password-policy
    "$REPO_ROOT/Scripts/check-secrets.sh"
    echo "check-secrets.sh: no password argv, Keychain call or logged secret"
}

# V12: a request that could prompt fails the row; preflight checks are listed (D-M5a-5). It watches the demos of
# V6–V11, so it refuses to run without them, and a log reader that fails is a failure, not "no request".
no_tcc_prompts() {
    local stream lines asked row
    for row in $DEMOS; do
        [[ " $DEMO_ROWS " == *" $row "* ]] ||
            { echo "V12 needs V6, V7, V8, V9, V10 and V11 in the same run (it checks what their demos asked for)"; return 1; }
    done
    stream=$("$LOG_TOOL" show --start "$DEMO_START" --style compact --predicate 'subsystem == "com.apple.TCC"') ||
        { echo "log show failed (status $?)"; return 1; }
    echo "TCC lines examined: $(grep -c . <<<"$stream" || true)"
    # An empty stream proves nothing (a window the log no longer holds, no privilege to read it): not a pass.
    [[ -n "$stream" ]] || { echo "the TCC stream was empty since $DEMO_START: nothing to check"; return 1; }
    lines=$(grep -i 'zivlet' <<<"$stream" || true)
    echo "preflight checks (listed, not failing):"
    grep 'preflight=yes' <<<"$lines" || echo "(none)"
    asked=$(grep 'preflight=no' <<<"$lines" || true)
    if [[ -n "$asked" ]]; then
        echo "requests that could prompt:"
        echo "$asked"
        return 1
    fi
    echo "no tccd request with preflight=no for Zivlet or its worker since $DEMO_START"
}

# V13 checks nothing against a base it cannot find (a shallow clone, a typo in ZIVLET_M7_BASE), so that fails.
base_known() {
    git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || { echo "unknown base $BASE"; return 1; }
    [[ -n "$(git rev-list "$BASE..HEAD")" ]] || { echo "no commits since $BASE: nothing to check"; return 1; }
}

# V13, part 1: every commit since BASE signed off and without Co-Authored-By.
commits_clean() {
    local commit commits status=0
    commits=$(git rev-list "$BASE..HEAD") || return 1
    for commit in $commits; do
        git log -1 --format=%B "$commit" | grep -q '^Signed-off-by: ' || { echo "not signed off: $commit"; status=1; }
        if git log -1 --format=%B "$commit" | grep -qi '^Co-Authored-By:'; then
            echo "Co-Authored-By: $commit"
            status=1
        fi
    done
    return "$status"
}

# V13, part 2: no changed source file at or over the limit, no personal or scratch path, no other app's name, no
# binary or PDF file and no new NSAlert added.
changes_clean() {
    local file files lines scratch added swift_added status=0
    files=$(git diff --name-only "$BASE..HEAD") || return 1
    added=$(git diff "$BASE..HEAD" | grep -E '^\+' || true)
    swift_added=$(git diff "$BASE..HEAD" -- '*.swift' | grep -E '^\+' || true)
    [[ -n "$files" ]] || { echo "no files changed since $BASE: nothing to check"; return 1; }
    while IFS= read -r file; do
        [[ -f "$file" && "$file" =~ \.(swift|sh|cc|h|md)$ ]] || continue
        lines=$(wc -l <"$file")
        ((lines < MAX_LINES)) || { echo "$file has $((lines)) lines"; status=1; }
    done <<<"$files"
    # Split so these lines do not match themselves.
    scratch="/private/tmp/""claude"
    if grep -E "/Users/$(whoami)([^a-z]|$)|$scratch" <<<"$added"; then
        echo "a personal path was added"
        status=1
    fi
    if grep -E "$PRIOR_ART_NAME" <<<"$added"; then
        echo "another app's name was added (describe prior art in our own words only)"
        status=1
    fi
    if git diff --numstat "$BASE..HEAD" | grep -E $'^-\t-\t'; then
        echo "a binary file was added"
        status=1
    fi
    if git diff --name-only --diff-filter=A "$BASE..HEAD" | grep -iE '\.pdf$'; then
        echo "a PDF file was added (test PDFs are made at test time, never committed)"
        status=1
    fi
    if grep 'NSAlert' <<<"$swift_added"; then
        echo "new code uses NSAlert (results go to toasts and cards, never modal alerts)"
        status=1
    fi
    return "$status"
}

# The source folders this checkout has.
source_dirs() {
    local dir
    for dir in $SOURCE_DIRS; do [[ -d "$dir" ]] && echo "$dir"; done
    return 0
}

# V13, part 3: what shipped code may not contain: print( (logs go to os.Logger), Vision outside EngineVision (P2-103),
# qpdf headers outside the shim (D-M7-16), a Keychain item call or a --password argument (P2-102).
sources_clean() {
    local dirs found status=0
    dirs=$(source_dirs)
    [[ -n "$dirs" ]] || return 0
    # shellcheck disable=SC2086  # one folder per word
    if grep -rnE '(^|[^[:alnum:]_.])print\(' $dirs; then
        echo "print( in shipped sources"
        status=1
    fi
    # shellcheck disable=SC2086
    found=$(grep -rlE '^[[:space:]]*(@[a-zA-Z]+ )*import Vision[[:space:]]*$' $dirs | grep -v "^$VISION_HOME" || true)
    [[ -z "$found" ]] || { printf 'import Vision outside EngineVision:\n%s\n' "$found"; status=1; }
    # shellcheck disable=SC2086
    found=$(grep -rlE '#[[:space:]]*include[[:space:]]*[<"]qpdf/' $dirs | grep -v "^$QPDF_HOME" || true)
    [[ -z "$found" ]] || { printf 'qpdf headers outside CZivletPDF:\n%s\n' "$found"; status=1; }
    # shellcheck disable=SC2086
    if grep -rnE "$KEYCHAIN_API" $dirs; then
        echo "a Keychain item API in shipped sources (passwords are never stored, P2-102)"
        status=1
    fi
    # shellcheck disable=SC2086
    if grep -rnF -- '--password' $dirs; then
        echo "a --password argument in shipped sources (a password never goes on a command line)"
        status=1
    fi
    return "$status"
}

# V13, part 4: the cap lint's count line per wheel list, kept in the log (P2-100).
cap_counts() {
    local counts=$LOGS/cap-counts.txt
    rm -f "$counts"
    make cap-lint COUNTS="$counts"
    [[ -s "$counts" ]] || { echo "the cap lint wrote no count lines"; return 1; }
    echo "cap lint counts:"
    cat "$counts"
    echo  # the report has no final newline
}

hygiene() {
    local status=0
    base_known || return 1
    commits_clean || status=1
    changes_clean || status=1
    sources_clean || status=1
    worker_entitlements_empty || status=1
    cap_counts || status=1
    ((status == 0)) && echo "hygiene clean since $BASE"
    return "$status"
}

# V3: the three earlier runners, each to the end (exit-lib.sh): a FAIL row fails V3, SKIP rows only skip it.
earlier_rows() {
    local status=0
    earlier_runner "$REPO_ROOT/Scripts/m5a-exit.sh" --only X2,X3,X4,X5 || status=1
    earlier_runner "$REPO_ROOT/Scripts/m5b-exit.sh" --only Y4,Y5,Y7 || status=1
    earlier_runner "$REPO_ROOT/Scripts/m6-exit.sh" --only Z4,Z5,Z7,Z8 || status=1
    return "$status"
}

run_row() {
    case "$1" in
        V1) gates ;;
        V2) make script-test ;;
        V3) earlier_rows ;;
        V4) timing ;;
        V5) qpdf_provenance ;;
        V6) make pdf-smoke ;;
        V7) password_policy ;;
        V8) make lock-demo ;;
        V9) make qr-demo ;;
        V10) make locked-input-demo ;;
        V11) make tool-states ;;
        V12) no_tcc_prompts ;;
        V13) hygiene ;;
    esac
}
