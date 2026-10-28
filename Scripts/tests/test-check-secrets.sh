#!/usr/bin/env bash
# check-secrets.sh (P2-102, plan 20c B7): every pattern refuses its positive sample and lets its negative sample pass,
# and the repository itself passes.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/Scripts" "$T/App" "$T/Worker" "$T/Packages/ZivletKit/Sources/ZivletUI/Password"
cp "$ROOT/Scripts/check-secrets.sh" "$T/Scripts/"
FILE="$T/App/A.swift"
clean='let name = "Report.pdf"'

refused() {  # sample, expected words, file
    printf '%s\n' "$1" >"${3:-$FILE}"
    local status=0 out
    out=$("$T/Scripts/check-secrets.sh" 2>&1) || status=$?
    assert_eq "$status" "1" "refused: $1"
    assert_contains "$out" "$2"
    printf '%s\n' "$clean" >"${3:-$FILE}"
}

allowed() {  # sample, file
    printf '%s\n' "$1" >"${2:-$FILE}"
    "$T/Scripts/check-secrets.sh" >/dev/null 2>&1 || fail "allowed: $1"
    printf '%s\n' "$clean" >"${2:-$FILE}"
}

printf '%s\n' "$clean" >"$FILE"
"$T/Scripts/check-secrets.sh" >/dev/null || fail "a clean tree passes"

# A password on a command line (argv shows in ps).
refused 'let arguments = ["--decrypt", "--password=\(typed)", input]' "password on a command line"
refused 'request.arguments.append("--password")' "password on a command line"
refused 'let args = ["qpdf", "password=" + typed]' "password on a command line" "$T/Worker/W.swift"
allowed '// qpdf has a --password flag; Zivlet never builds one'
allowed 'let label = "Password"'
allowed 'let arguments = ["-i", input.path, output.path]'

# Keychain item APIs, anywhere.
refused 'let status = SecItemAdd(query as CFDictionary, nil)' "Keychain"
refused 'SecItemCopyMatching(query, &item)' "Keychain"
refused 'SecItemUpdate(query, changes)' "Keychain"
refused 'SecItemDelete(query)' "Keychain"
refused 'let query = [kSecClass: kSecClassGenericPassword]' "Keychain" "$T/Packages/ZivletKit/Sources/ZivletUI/K.swift"
allowed 'let item = NSPasteboardItem()'

# The system's password generator only in its own file.
refused 'let made = SecCreateSharedWebCredentialPassword()' "outside SystemPasswordSuggester.swift"
allowed 'guard let made = SecCreateSharedWebCredentialPassword() else { return nil }' \
    "$T/Packages/ZivletKit/Sources/ZivletUI/Password/SystemPasswordSuggester.swift"

# A secret interpolated into a log line, at any privacy level.
refused 'logger.error("Unlock failed: \(password, privacy: .private)")' "logged"
refused 'logger.notice("\(sheet.password)")' "logged"
refused 'Logger(subsystem: "s", category: "app").debug("\(secret)")' "logged"
refused 'os_log("%@", "\(passphrase)")' "logged"
refused 'logger.info("\(secrets.input as JobSecret?)")' "logged"
allowed 'logger.notice("Unlock finished: \(count, privacy: .public) files")'
allowed 'logger.error("Wrong password for \(fileCount, privacy: .public) files")'

"$ROOT/Scripts/check-secrets.sh" || fail "the repository itself fails the check"
echo "PASS test-check-secrets"
