#!/usr/bin/env bash
# Clean-VM smoke test of a release DMG (P1-53, owner step O-4): clones the Tart image ZIVLET_TART_IMAGE (macOS 26.0,
# with ssh key login for ZIVLET_TART_USER, default admin), shares the DMG's folder read-only, and in the guest
# mounts the DMG, asks Gatekeeper about the app (it must say "Notarized Developer ID" unless --adhoc), copies the app
# out, encodes one second of video with the bundled ffmpeg, checks it with the bundled ffprobe, and launches the app.
# The clone is always deleted. Release builds ignore the DEBUG demo arguments, so conversions through the app itself
# stay a Debug-build check (Scripts/demo-convert.sh). Without Tart or an image: exit 3.
# Usage: Scripts/vm-smoke.sh <Zivlet-<version>.dmg> [--adhoc]
set -euo pipefail
OWNER_STEP="The VM smoke test needs the owner's Tart host and a macOS 26.0 image in ZIVLET_TART_IMAGE (owner step O-4)."
DMG=${1:?usage: vm-smoke.sh <dmg> [--adhoc]}
EXPECT=notarized
[[ "${2:-}" == "--adhoc" ]] && EXPECT=adhoc
[[ -f "$DMG" && "$DMG" == *.dmg ]] || { echo "error: $DMG is not a DMG" >&2; exit 1; }
if [[ -z "${ZIVLET_TART_IMAGE:-}" ]] || ! command -v tart >/dev/null 2>&1; then echo "$OWNER_STEP" >&2; exit 3; fi
GUEST_USER=${ZIVLET_TART_USER:-admin}
BOOT_SECONDS=${ZIVLET_TART_BOOT_SECONDS:-180}
SSH_TRIES=30
DIR=$(cd "$(dirname "$DMG")" && pwd)
NAME=$(basename "$DMG")
VM=zivlet-smoke-$$
RUN_PID=""

read -r -d '' GUEST <<'EOF' || true
set -euo pipefail
NAME=$1; EXPECT=$2
MNT=$(mktemp -d /tmp/zivlet-dmg.XXXXXX)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "/Volumes/My Shared Files/release/$NAME"
verdict=$(spctl -a -vv -t exec "$MNT/Zivlet.app" 2>&1 || true)
echo "Gatekeeper: $verdict"
if [ "$EXPECT" = notarized ] && ! echo "$verdict" | grep -q "source=Notarized Developer ID"; then exit 1; fi
mkdir -p "$HOME/Applications"
ditto "$MNT/Zivlet.app" "$HOME/Applications/Zivlet.app"
hdiutil detach -quiet "$MNT"
APP=$HOME/Applications/Zivlet.app
"$APP/Contents/Helpers/ffmpeg" -hide_banner -loglevel error -f lavfi -i testsrc2=duration=1:size=320x240:rate=10 \
    -c:v libx264 -pix_fmt yuv420p -y /tmp/zivlet-smoke.mp4
"$APP/Contents/Helpers/ffprobe" -v error -show_entries stream=codec_name -of csv=p=0 /tmp/zivlet-smoke.mp4 |
    grep -qx h264
open "$APP"
sleep 5
pgrep -x Zivlet >/dev/null || { echo "Zivlet did not stay running"; exit 1; }
pkill -x Zivlet || true
echo ZIVLET-SMOKE-OK
EOF

cleanup() {
    [[ -n "$RUN_PID" ]] && kill "$RUN_PID" 2>/dev/null
    tart stop "$VM" >/dev/null 2>&1 || true
    tart delete "$VM" >/dev/null 2>&1 || true
}
tart clone "$ZIVLET_TART_IMAGE" "$VM"
trap cleanup EXIT
tart run "$VM" --no-graphics "--dir=release:$DIR:ro" >/dev/null 2>&1 &
RUN_PID=$!

ip=""
for ((waited = 0; waited < BOOT_SECONDS; waited += 2)); do
    ip=$(tart ip "$VM" 2>/dev/null || true)
    [[ -n "$ip" ]] && break
    sleep 2
done
[[ -n "$ip" ]] || { echo "error: $VM had no IP address after $BOOT_SECONDS s" >&2; exit 1; }

# ssh exits 255 while the guest's sshd is still starting; any other status is the guest script's.
for ((try = 1; try <= SSH_TRIES; try++)); do
    status=0
    out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$GUEST_USER@$ip" \
        bash -s -- "$NAME" "$EXPECT" <<<"$GUEST" 2>&1) || status=$?
    [[ $status -ne 255 ]] && break
    sleep 5
done
echo "$out"
if [[ $status -ne 0 ]] || ! grep -q "ZIVLET-SMOKE-OK" <<<"$out"; then
    echo "error: the VM smoke test failed on $ZIVLET_TART_IMAGE" >&2
    exit 1
fi
echo "VM smoke OK on $ZIVLET_TART_IMAGE ($EXPECT)"
