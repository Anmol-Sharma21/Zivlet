#!/usr/bin/env bash
# The GitHub workflows (P0-07, P0-37, P1-53) run only on our self-hosted runner, never on pull_request_target, with
# least-privilege permissions, actions pinned by commit SHA and no secrets outside the release workflow. Parsed with
# the system Ruby's YAML (Python has no YAML module on macOS).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WF=$ROOT/.github/workflows
for name in ci nightly vendor release; do assert_file "$WF/$name.yml"; done

read -r -d '' CHECKER <<'RUBY' || true
problems = []
check = ->(ok, message) { problems << message unless ok }
Dir.glob(File.join(ARGV[0], "*.yml")).sort.each do |path|
  name = File.basename(path, ".yml")
  text = File.read(path)
  doc = YAML.safe_load(text)
  triggers = doc["on"] || doc[true] || {}
  check.(!text.include?("pull_request_target"), "#{name}: uses pull_request_target")
  check.(doc["concurrency"].to_s.include?("github.ref"), "#{name}: no per-ref concurrency")
  check.(doc.dig("env", "DEVELOPER_DIR") == "/Applications/Xcode.app/Contents/Developer",
         "#{name}: DEVELOPER_DIR not set")
  text.scan(/uses:\s*(\S+)/).flatten.each do |ref|
    check.(ref =~ /\A[\w.-]+\/[\w.\/-]+@[0-9a-f]{40}\z/, "#{name}: action not pinned to a commit SHA: #{ref}")
  end
  unless name == "release"
    check.(doc["permissions"] == { "contents" => "read" }, "#{name}: permissions must be contents: read only")
    check.(!text.include?("secrets."), "#{name}: references secrets")
  end
  (doc["jobs"] || {}).each do |job_name, job|
    labels = Array(job["runs-on"])
    check.(labels.include?("self-hosted") && labels.any? { |l| l.to_s.start_with?("zivlet") },
           "#{name}/#{job_name}: runs-on must be self-hosted with a zivlet label")
    check.(job["permissions"].nil?, "#{name}/#{job_name}: job widens permissions") unless name == "release"
  end
  check.(!triggers.nil?, "#{name}: no triggers")
  # Code from a fork never runs on the persistent self-hosted runner (it could poison the shared vendor cache).
  if triggers.is_a?(Hash) && triggers.key?("pull_request")
    (doc["jobs"] || {}).each do |job_name, job|
      check.(job["if"].to_s.include?("github.event.pull_request.head.repo.full_name == github.repository"),
             "#{name}/#{job_name}: pull requests from forks must not run on the self-hosted runner")
    end
  end
end
ci = File.read(File.join(ARGV[0], "ci.yml"))
["make lint", "make test", "make coverage", "make release-check", "make licence-gate", "make vendor-test"].each do |cmd|
  check.(ci =~ /^\s*run:.*\b#{Regexp.escape(cmd)}\b/, "ci: does not run #{cmd}")
end
nightly = YAML.safe_load(File.read(File.join(ARGV[0], "nightly.yml")))
nightly_env = nightly["jobs"].values.map { |j| (j["env"] || {}).merge(*(j["steps"] || []).map { |s| s["env"] || {} }) }
check.(nightly_env.any? { |e| e["ZIVLET_MATRIX"] == "full" }, "nightly: ZIVLET_MATRIX is not full")
check.(((nightly["on"] || nightly[true]) || {}).key?("schedule"), "nightly: no schedule")
vendor = YAML.safe_load(File.read(File.join(ARGV[0], "vendor.yml")))
paths = (((vendor["on"] || vendor[true]) || {}).values.compact.map { |t| t["paths"] }).flatten.compact
check.(paths.include?("Vendor/**"), "vendor: not triggered by Vendor/**")
# Release (P1-53): protected environment, write access to contents only, dry run by default, secrets only in the
# env of the steps that need them (never in workflow or job env, never pasted into a run script).
rtext = File.read(File.join(ARGV[0], "release.yml"))
release = YAML.safe_load(rtext)
rtriggers = release["on"] || release[true] || {}
check.(Array(rtriggers.dig("push", "tags")).include?("v*"), "release: not triggered by v* tags")
dry = rtriggers.dig("workflow_dispatch", "inputs", "dry_run") || {}
check.(dry["type"] == "boolean" && dry["default"] == true, "release: dry_run must be a boolean defaulting to true")
check.(release["permissions"] == { "contents" => "write" }, "release: permissions must be contents: write only")
check.(!(release["env"] || {}).to_s.include?("secrets."), "release: secrets in workflow env")
release["jobs"].each do |job_name, job|
  environment = job["environment"].is_a?(Hash) ? job["environment"]["name"] : job["environment"]
  check.(environment == "release", "release/#{job_name}: must use environment: release")
  check.(Array(job["runs-on"]).include?("zivlet-release"), "release/#{job_name}: not on the zivlet-release runner")
  check.(job["permissions"].nil?, "release/#{job_name}: job changes permissions")
  check.(!(job["env"] || {}).to_s.include?("secrets."), "release/#{job_name}: secrets in job env")
  job["steps"].each do |step|
    check.(!step["run"].to_s.include?("secrets."), "release/#{job_name}: secret in a run script: #{step["name"]}")
    if (step["env"] || {}).to_s.include?("secrets.")
      check.(step["name"].to_s =~ /mode|notar|appcast/i, "release/#{job_name}: secrets in step: #{step["name"]}")
    end
  end
end
%w[sign-app.sh verify-signatures.sh notarize.sh make-dmg.sh size-gate.sh source-bundle.sh sbom.sh make-appcast.sh
   vm-smoke.sh].each { |s| check.(rtext.include?("Scripts/#{s}"), "release: does not run Scripts/#{s}") }
check.(rtext.include?("gh release create") && rtext.include?("--draft"), "release: no draft release")
# The signed build never takes vendor outputs or old DMGs from a cache other jobs can write.
check.(!rtext.include?("RUNNER_TOOL_CACHE"), "release: uses the shared runner tool cache")
check.(rtext =~ /run:\s*Scripts\/ci-vendor\.sh --from-source\s*$/, "release: vendor outputs not built from source")
check.(rtext.include?("ZIVLET_RELEASE_FEED_DIR"), "release: appcast feed directory is not the release-only one")
if problems.empty? then puts "workflows OK" else puts problems; exit 1 end
RUBY
out=$(/usr/bin/ruby -ryaml -e "$CHECKER" "$WF" 2>&1) || fail "$out"
assert_contains "$out" "workflows OK"

# make ci-local runs the run steps of ci.yml in order: the dry list must match the workflow.
listed=$("$ROOT/Scripts/ci-local.sh" --list)
assert_contains "$listed" "make lint"
assert_contains "$listed" "make release-check"
first=$(head -1 <<<"$listed"); assert_eq "$first" "make vendor-test" "first ci-local step"
grep -q '^ci-local:' "$ROOT/Makefile" || fail "Makefile has no ci-local target"

# A run step with a GitHub expression cannot run locally, so ci-local refuses it rather than guessing.
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
printf 'jobs:\n  a:\n    steps:\n      - run: echo ${{ github.sha }}\n' >"$T/ci.yml"
out=$("$ROOT/Scripts/ci-local.sh" --workflow "$T/ci.yml" --list 2>&1 || true)
assert_contains "$out" "GitHub expression"
assert_fails "$ROOT/Scripts/ci-local.sh" --workflow "$T/ci.yml" --list
echo "PASS test-workflows"
