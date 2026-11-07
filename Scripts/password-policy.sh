#!/usr/bin/env bash
# Exit row V7 (plan 20c B7, P2-102): the password policy suites by name, then the source grep's own test. A
# `swift test --filter` that matched nothing exits 0, so a run without a passing policy test fails here.
# Usage: Scripts/password-policy.sh      (from make password-policy, which sets up the native binary targets)
set -euo pipefail
source "$(dirname "$0")/env.sh"
SUITES="PasswordPolicyTests|ProtectPolicyTests|PasswordSettingsPolicyTests|JobSecretTests|WireSecretTests"
SUITES+="|WireSecretsTests|BatchSecretsTests|WorkerSecretsXPCTests"

out=$(cd "$KIT" && swift test --filter "$SUITES" 2>&1) || { echo "$out"; exit 1; }
runs=$(grep -E '^. Test run with [1-9][0-9]* tests? .*passed' <<<"$out" || true)
[[ -n "$runs" ]] || { echo "$out"; echo "password-policy: no policy test ran" >&2; exit 1; }
echo "$runs"
bash "$REPO_ROOT/Scripts/tests/test-check-secrets.sh"
echo "password-policy: the policy suites and the grep's test pass"
