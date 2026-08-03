#!/bin/bash
#
# Captures App Store screenshots on every required device size.
#
#   ./Scripts/capture-screenshots.sh
#
# Screenshots land in fastlane/screenshots/en-US/ at the exact pixel sizes App
# Store Connect requires. On the simulator the app is backed by
# FixtureSleepStore, so captures show a full multi-stage night without needing
# HealthKit data on the host.
#
# The simulator status bar is overridden to 9:41 with full signal and a charged
# battery, matching Apple's own marketing convention.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="SleepDaddyScreenshots"
OUTPUT_DIR="fastlane/screenshots/en-US"
DERIVED_DATA="./DerivedData"

# One entry per App Store Connect screenshot slot, as "label|device type id".
# The script creates each simulator on the newest installed iOS runtime rather
# than relying on whatever happens to be set up locally — the 6.5" devices in
# particular usually only exist on runtimes too old for our deployment target.
#
#   iPhone 17 Pro Max -> 1320 x 2868 (6.9" slot)
#   iPhone 14 Plus    -> 1284 x 2778 (6.5" slot; 1242 x 2688 also accepted)
#   iPad Pro 13-inch  -> 2064 x 2752 (13"  slot)
DEVICES=(
  "iPhone 6.9|com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
  "iPhone 6.5|com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus"
  "iPad 13|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-16GB"
)

# Newest first, so we prefer the most current runtime and fall back if a device
# type isn't supported there.
RUNTIMES=($(xcrun simctl list runtimes | awk '/^iOS /{print $NF}' | tail -r))

resolve_simulator() {
  # Reuses a dedicated simulator per slot so repeat runs don't pile up devices.
  local label="$1" device_type="$2"
  local name="SleepDaddy Shots - $label"
  local udid

  udid="$(
    xcrun simctl list devices \
      | grep -F "$name (" \
      | head -1 \
      | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
  )"
  if [ -n "$udid" ]; then
    echo "$udid"
    return 0
  fi

  for runtime in "${RUNTIMES[@]}"; do
    if udid="$(xcrun simctl create "$name" "$device_type" "$runtime" 2>/dev/null)"; then
      echo "$udid"
      return 0
    fi
  done

  echo "Could not create a simulator for '$label' ($device_type)." >&2
  echo "Install a current iOS runtime via Xcode > Settings > Components." >&2
  return 1
}

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

echo "==> Generating Xcode project"
./generate.sh >/dev/null

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

for entry in "${DEVICES[@]}"; do
  device="${entry%%|*}"
  device_type="${entry##*|}"
  echo "==> $device"

  udid="$(resolve_simulator "$device" "$device_type")"

  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

  # Marketing status bar. Cellular bars are rejected on Wi-Fi-only iPads, so
  # only request them where they apply.
  status_bar_args=(--time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3)
  case "$device" in
    iPhone*) status_bar_args+=(--cellularBars 4) ;;
  esac
  xcrun simctl status_bar "$udid" override "${status_bar_args[@]}" >/dev/null 2>&1 || true

  result_bundle="$WORK_DIR/${device// /_}.xcresult"
  rm -rf "$result_bundle"

  echo "    running capture pass"
  # DemoWalkthrough shares this target so it shares the app build, but it is the
  # App Review video pass and attaches no screenshots. Left in, it would add its
  # 75-second run to every device here for nothing.
  xcodebuild test \
    -scheme "$SCHEME" \
    -skip-testing:SleepDaddyScreenshots/DemoWalkthrough \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_bundle" \
    CODE_SIGNING_ALLOWED=NO \
    >"$WORK_DIR/${device// /_}.log" 2>&1 \
    || { echo "Capture failed. Log: $WORK_DIR/${device// /_}.log" >&2; exit 1; }

  raw_dir="$WORK_DIR/raw_${device// /_}"
  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$raw_dir" >/dev/null

  echo "    exporting to $OUTPUT_DIR"
  DEVICE_LABEL="$device" RAW_DIR="$raw_dir" OUT_DIR="$OUTPUT_DIR" python3 - <<'PY'
import json, os, re, shutil, subprocess

raw = os.environ["RAW_DIR"]
out = os.environ["OUT_DIR"]
label = os.environ["DEVICE_LABEL"]

with open(os.path.join(raw, "manifest.json")) as fh:
    manifest = json.load(fh)

for test in manifest:
    for attachment in test.get("attachments", []):
        name = re.sub(
            r"_\d+_[0-9A-F-]+\.png$", ".png", attachment["suggestedHumanReadableName"]
        )
        dest = os.path.join(out, f"{label} {name}")
        shutil.copy(os.path.join(raw, attachment["exportedFileName"]), dest)

        # XCUIScreen captures always come back in the device's native portrait
        # dimensions, so landscape screens arrive rotated. App Store Connect
        # rejects those; rotate them back to true landscape.
        if "landscape" in name:
            subprocess.run(
                ["sips", "--rotate", "270", dest, "--out", dest],
                check=True, capture_output=True,
            )
PY
done

echo
echo "==> Done"
for f in "$OUTPUT_DIR"/*.png; do
  printf '%s  %s\n' \
    "$(sips -g pixelWidth -g pixelHeight "$f" | grep -oE '[0-9]+$' | paste -sd'x' -)" \
    "$(basename "$f")"
done
