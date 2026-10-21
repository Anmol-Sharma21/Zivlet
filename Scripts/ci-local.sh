#!/usr/bin/env bash
# Runs the run steps of .github/workflows/ci.yml in order on this Mac (make ci-local), with the workflow's env, so a
# change can be checked exactly as the self-hosted runner would check it. `uses:` steps (checkout, uploads) are
# skipped. A run step or env value with a GitHub expression cannot run here, so it is refused, not guessed.
# Usage: Scripts/ci-local.sh [--workflow FILE] [--list]
set -euo pipefail
source "$(dirname "$0")/env.sh"
WORKFLOW=$REPO_ROOT/.github/workflows/ci.yml
LIST=0
while (($#)); do
    case "$1" in
        --workflow) WORKFLOW=${2:?--workflow needs a file}; shift 2 ;;
        --list) LIST=1; shift ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
done
[[ -f "$WORKFLOW" ]] || { echo "error: $WORKFLOW not found" >&2; exit 1; }

# Prints NUL-separated records: "env NAME=VALUE" for workflow and job env, then "run SCRIPT" per step, in order.
steps() {
    /usr/bin/ruby -ryaml -e '
        doc = YAML.safe_load(File.read(ARGV[0])) || {}
        records = (doc["env"] || {}).map { |k, v| "env #{k}=#{v}" }
        (doc["jobs"] || {}).each_value do |job|
          records += (job["env"] || {}).map { |k, v| "env #{k}=#{v}" }
          (job["steps"] || []).each { |s| records << "run #{s["run"].strip}" if s["run"] }
        end
        bad = records.find { |r| r.include?("${{") }
        abort "error: a GitHub expression cannot run locally: #{bad}" if bad
        print records.map { |r| r + "\0" }.join' "$WORKFLOW"
}

records=$(steps | tr '\0' '\036') || exit 1
IFS=$'\036' read -r -d '' -a items <<<"$records" || true
for item in "${items[@]}"; do
    [[ -n "${item//[$'\n']/}" ]] || continue
    kind=${item%% *}; body=${item#* }
    if [[ "$kind" == "env" ]]; then export "${body?}"; continue; fi
    if ((LIST)); then echo "$body"; continue; fi
    echo "==> $body"
    (cd "$REPO_ROOT" && bash --noprofile --norc -euo pipefail -c "$body") || {
        echo "error: ci-local stopped at: $body" >&2
        exit 1
    }
done
if ((!LIST)); then echo "ci-local: every ci.yml step passed"; fi
