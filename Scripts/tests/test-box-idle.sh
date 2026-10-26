#!/usr/bin/env bash
# box-idle.sh measures the Debug app's idle CPU with the Drop Box panel shown and still, with the tray resting on its
# sensor and with the real armed demo box, each minus a baseline (plan 16 E5, Y8). Here the launcher, pgrep and the sampler are stand-ins: the
# sampler gives the app's values in turn (and 1.0 for WindowServer), so the limit and the baseline rule are checked
# without launching anything.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/box-idle.sh
grep -q '^box-idle:' "$ROOT/Makefile" || fail "Makefile has no box-idle target"

out=$(ZIVLET_IDLE_DRY_RUN=1 "$SCRIPT")
assert_contains "$out" "build/DerivedData/Build/Products/Debug/Zivlet.app"
assert_contains "$out" "state baseline baseline"
assert_contains "$out" "state panel-still 0.1 "
assert_contains "$out" "-ZivletBoxPreview grid"
assert_contains "$out" "state tray-sensor 0.1 "
assert_contains "$out" "-ZivletTrayPreview sensor"
assert_contains "$out" "state box-armed 0.1 "
assert_contains "$out" "-ZivletBoxDemo"
assert_contains "$out" "120 s each"
if grep -q "fastProgress" <<<"$out"; then fail "G-M5a-1's fast-progress row is not part of box-idle"; fi

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/Zivlet.app"
printf '#!/usr/bin/env bash\necho "$*" >>"%s/opened"\n' "$T" >"$T/bin/open"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/osascript"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/pkill"
printf '#!/usr/bin/env bash\n[[ "$*" == *WindowServer* ]] && echo 88 || echo 123\n' >"$T/bin/pgrep"
# The app's next value from FAKE_SAMPLES (one per call, in order); an empty word stands for a failed sample.
cat >"$T/bin/sampler" <<SAMPLER
#!/usr/bin/env bash
[[ "\$1" == 88 ]] && { echo 1.000; exit 0; }
n=\$(cat "$T/count" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$T/count"
IFS=, read -r -a values <<<"\$FAKE_SAMPLES"
value=\${values[\$n]:-}
[[ -n "\$value" ]] || exit 2
echo "\$value"
SAMPLER
chmod +x "$T/bin/"*
run() {
    rm -f "$T/count"
    PATH=$T/bin:$PATH ZIVLET_IDLE_APP=$T/Zivlet.app ZIVLET_IDLE_SAMPLER=$T/bin/sampler ZIVLET_IDLE_SETTLE=0 \
        ZIVLET_IDLE_SECONDS=1 FAKE_SAMPLES=$1 "$SCRIPT"
}
out=$(run "0.500,0.590,0.590,0.550") || fail "0.09 over the baseline passes: $out"
assert_contains "$out" "panel-still 0.590 % (over baseline 0.090 %, limit 0.1 %) pass"
assert_contains "$out" "tray-sensor 0.590 % (over baseline 0.090 %, limit 0.1 %) pass"
assert_contains "$out" "WindowServer 1.000 %"
assert_contains "$(cat "$T/opened")" "-ZivletBoxPreview grid"
assert_contains "$out" "box-armed 0.550 % (over baseline 0.050 %, limit 0.1 %) pass"
grep -q -- "-ZivletBoxDemo .*zivlet-box-idle\." "$T/opened" || fail "the armed state opens the demo over its scratch folder"
if grep -q "@DEMO@" "$T/opened"; then fail "the scratch folder replaces the placeholder"; fi

status=0; out=$(run "0.500,0.590,0.610,0.550") || status=$?
assert_eq "$status" "1" "0.11 over the baseline fails"
assert_contains "$out" "tray-sensor 0.610 % (over baseline 0.110 %, limit 0.1 %) FAIL"

status=0; out=$(run ",0.590,0.590,0.590" 2>&1) || status=$?
assert_eq "$status" "1" "a missing baseline is refused"
assert_contains "$out" "no baseline"
echo "PASS test-box-idle"
