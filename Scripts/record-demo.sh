#!/bin/bash
#
# Records the App Review demo video.
#
#   ./Scripts/record-demo.sh
#
# Runs the DemoWalkthrough UI test on a simulator while `simctl io recordVideo`
# captures the screen, then transcodes the capture to an H.264 MP4 sized for the
# web at web/demo/sleepdaddy-demo.mp4. The unscaled capture and the build logs
# stay in build/demo/.
#
# The video carries no chapter marks. recordVideo emits a frame only when the
# screen changes, and its timestamps do not advance faithfully through a static
# pause, so wall-clock marks taken during the run land seconds off in either
# direction once mapped onto the recording. The demo page lists the sections in
# order instead.
#
# On the simulator the app is backed by FixtureSleepStore, so the walkthrough
# shows a full multi-stage night without needing HealthKit data on the host. The
# published page says so; do not present this as a real Apple Watch recording.
#
# The simulator status bar is overridden to 9:41 with full signal and a charged
# battery, matching Apple's own marketing convention.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="SleepDaddyScreenshots"
ONLY_TESTING="SleepDaddyScreenshots/DemoWalkthrough"
DEVICE_NAME="SleepDaddy Demo"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
DERIVED_DATA="./DerivedData"
WORK_DIR="build/demo"
PUBLISH_DIR="web/demo"
RAW="$WORK_DIR/demo-raw.mov"
WEB="$PUBLISH_DIR/sleepdaddy-demo.mp4"

# Height of the web copy. The capture comes off the device at native pixel size;
# 1280 tall keeps the timeline legible at a fraction of the file size.
WEB_HEIGHT=1280

# The springboard is trimmed off both ends by looking at the picture rather than
# the clock, because the capture's timestamps do not track wall clock (see the
# note above). The home screen wallpaper is strongly coloured and every screen of
# the app is near-neutral, so mean saturation separates them cleanly: the
# wallpaper measures around 12, the app around 3, and its loading screen near 0.
SPRINGBOARD_SATURATION=8

# Seconds of slack left either side of the detected app frames, so the cut never
# clips the first or last frame of the walkthrough.
TRIM_PAD=0.2

# The capture is variable frame rate — long static stretches emit almost no
# frames — which browsers play back as a stutter. Everything downstream is
# resampled to this constant rate.
FPS=30

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }
command -v ffmpeg   >/dev/null || { echo "ffmpeg not found: brew install ffmpeg" >&2; exit 1; }

# Newest first, so we prefer the most current runtime and fall back if the device
# type isn't supported there.
RUNTIMES=($(xcrun simctl list runtimes | awk '/^iOS /{print $NF}' | tail -r))

resolve_simulator() {
  # Reuses a dedicated simulator so repeat runs don't pile up devices, and so the
  # recording never inherits state from a simulator being used for something else.
  local udid
  # No match is the ordinary first-run case, not an error — the creation loop
  # below handles it. Say so with `|| true` so the lookup stays safe under
  # `set -e` wherever this function ends up being called from.
  # `available` excludes devices whose runtime has since been removed. Without it
  # a stale entry still matches by name and hands back a valid-looking UDID that
  # cannot boot, and the creation loop below never runs.
  udid="$(
    xcrun simctl list devices available \
      | grep -F "$DEVICE_NAME (" \
      | head -1 \
      | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
      || true
  )"
  if [ -n "$udid" ]; then
    echo "$udid"
    return 0
  fi

  for runtime in "${RUNTIMES[@]}"; do
    if udid="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$runtime" 2>/dev/null)"; then
      echo "$udid"
      return 0
    fi
  done

  echo "Could not create a simulator ($DEVICE_TYPE)." >&2
  echo "Install a current iOS runtime via Xcode > Settings > Components." >&2
  return 1
}

echo "==> Generating Xcode project"
./generate.sh >/dev/null

mkdir -p "$WORK_DIR" "$PUBLISH_DIR"
rm -f "$RAW" "$WEB" "$WORK_DIR/record.log"

UDID="$(resolve_simulator)"
echo "==> Simulator $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

BUILD_LOG="$WORK_DIR/build.log"
TEST_LOG="$WORK_DIR/xcodebuild.log"

# Build and install ahead of the recording. Doing this inside the recording would
# put ten-plus seconds of springboard at the front of the video.
echo "==> Building"
xcodebuild build-for-testing \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  >"$BUILD_LOG" 2>&1 \
  || { echo "Build failed. Log: $BUILD_LOG" >&2; exit 1; }

echo "==> Recording"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW" >"$WORK_DIR/record.log" 2>&1 &
RECORD_PID=$!

# recordVideo only finalizes the file on SIGINT, so make sure it gets one even if
# the test run dies partway through.
cleanup() {
  if kill -0 "$RECORD_PID" 2>/dev/null; then
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "    running walkthrough"
set +e
xcodebuild test-without-building \
  -scheme "$SCHEME" \
  -only-testing:"$ONLY_TESTING" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  >"$TEST_LOG" 2>&1
TEST_STATUS=$?
set -e

# Let the recorder run past the end of the run so the finalized file definitely
# contains the last frame we care about; the tail is trimmed below.
sleep 2

cleanup
trap - EXIT

if [ "$TEST_STATUS" -ne 0 ]; then
  echo "Walkthrough failed. Log: $TEST_LOG" >&2
  exit 1
fi

[ -s "$RAW" ] || { echo "Recording produced no video at $RAW" >&2; exit 1; }

echo "==> Finding the walkthrough"
# Sampling at 4 Hz is plenty to place a cut within the pad, and keeps the analysis
# pass short.
BOUNDS="$(
  ffmpeg -v error -i "$RAW" \
    -vf "fps=4,signalstats,metadata=print:key=lavfi.signalstats.SATAVG:file=-" \
    -f null - 2>/dev/null \
  | SPRINGBOARD_SATURATION="$SPRINGBOARD_SATURATION" TRIM_PAD="$TRIM_PAD" python3 -c '
import os, re, sys

threshold = float(os.environ["SPRINGBOARD_SATURATION"])
pad = float(os.environ["TRIM_PAD"])

time, app_times = None, []
for line in sys.stdin:
    match = re.search(r"pts_time:([0-9.]+)", line)
    if match:
        time = float(match.group(1))
        continue
    match = re.search(r"SATAVG=([0-9.]+)", line)
    if match and time is not None and float(match.group(1)) < threshold:
        app_times.append(time)

if not app_times:
    raise SystemExit("Never found an app frame in the capture")

start = max(0.0, app_times[0] - pad)
print(f"{start:.3f} {app_times[-1] - start + pad:.3f}")
'
)"
START="${BOUNDS%% *}"
KEEP="${BOUNDS##* }"
echo "    app runs from ${START}s for ${KEEP}s"

echo "==> Transcoding"
# yuv420p and +faststart are what make the file play inline in Safari and Chrome
# rather than only downloading; the fps filter turns the variable-rate capture
# into something that plays smoothly.
ffmpeg -y -loglevel error -ss "$START" -i "$RAW" -t "$KEEP" \
  -vf "scale=-2:$WEB_HEIGHT,fps=$FPS" \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 23 -preset slow \
  -movflags +faststart -an -fps_mode cfr \
  "$WEB"

echo
echo "==> Done"
for f in "$RAW" "$WEB"; do
  printf '%s  %s  %s\n' \
    "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$f")" \
    "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" | cut -d. -f1)s" \
    "$f"
done
