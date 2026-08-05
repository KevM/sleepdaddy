#!/bin/bash
#
# Runs the unit test suite against a pinned simulator, and stops waiting once
# the results are in.
#
#   ./Scripts/run-tests.sh
#   ./Scripts/run-tests.sh -only-testing:SleepDaddyTests/NightBrowserModelTests
#
# Any extra arguments are passed straight through to xcodebuild.
#
# Two reasons this exists rather than calling xcodebuild directly.
#
# A `name=iPhone 17` destination is ambiguous the moment two installed runtimes
# both carry that device name, and which one xcodebuild picks is not pinned. If
# it lands on a shut-down device it has to boot another simulator before the
# tests can start. This resolves a single UDID up front, newest runtime first.
#
# More importantly, xcodebuild frequently never exits *after* the tests have
# finished. The log holds the whole run and its `Test run with N tests` summary,
# and then the process sits there indefinitely, blocked in CoreSimulator
# teardown — `sample` puts it in -[Xcode3CommandLineBuildTool
# waitForBuildWithBuildLog:] on a mach_msg that never arrives. Measured here at
# roughly two runs in three. It is not related to how many simulators are booted
# (it happens just as readily from a clean `simctl shutdown all`), and it is why
# testing from Xcode takes seconds while the CLI appears to hang: the IDE holds
# one long-lived simulator session and never performs this teardown at all.
#
# So this watches the log for the summary line instead of waiting on the
# process. Once every test has reported, the run is over as far as we are
# concerned; xcodebuild gets a few seconds to exit on its own, and is killed if
# it will not. Pass/fail then comes from the summary line rather than from an
# exit code we may never receive.
#
# TEST_TIMEOUT only guards a run that never produces results at all, such as a
# build failure that wedges.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="SleepDaddy"
DERIVED_DATA="./DerivedData"
DEVICE_NAME="${SIM_DEVICE_NAME:-iPhone 17}"
TIMEOUT="${TEST_TIMEOUT:-300}"
GRACE=5
LOG="build/test-run.log"

# Exact name match under the newest iOS runtime that has one. `iPhone 17 (` will
# not match `iPhone 17 Pro (`.
udid="$(
  xcrun simctl list devices available \
    | awk -v want="$DEVICE_NAME" '
        /^-- iOS / { rt = $3; next }
        /^-- /     { rt = "";  next }
        rt == ""   { next }
        {
          line = $0
          sub(/^[ \t]+/, "", line)
          if (index(line, want " (") == 1 &&
              match(line, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/))
            print rt "\t" substr(line, RSTART, RLENGTH)
        }
      ' \
    | sort -rV \
    | head -1 \
    | cut -f2
)"

if [ -z "$udid" ]; then
  echo "No available simulator named '$DEVICE_NAME'." >&2
  echo "Set SIM_DEVICE_NAME, or install a runtime via Xcode > Settings > Components." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG")"
: >"$LOG"

echo "==> $DEVICE_NAME ($udid)"

set +e
xcodebuild test \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$DERIVED_DATA" \
  "$@" \
  >"$LOG" 2>&1 &
pid=$!

waited=0
stalled=0
while :; do
  if grep -q "Test run with .* tests" "$LOG" 2>/dev/null; then
    # Results are in. Give it a moment to exit cleanly anyway — when teardown
    # behaves, that is the tidier outcome.
    grace=0
    while kill -0 "$pid" 2>/dev/null && [ "$grace" -lt "$GRACE" ]; do
      sleep 1
      grace=$((grace + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      stalled=1
      pkill -P "$pid" 2>/dev/null
      kill -9 "$pid" 2>/dev/null
    fi
    break
  fi

  # Exited without ever reporting a test run — a build failure, most likely.
  kill -0 "$pid" 2>/dev/null || break

  if [ "$waited" -ge "$TIMEOUT" ]; then
    pkill -P "$pid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo >&2
    echo "xcodebuild hung after ${TIMEOUT}s without the test run ever completing." >&2
    echo "Last line of the log:" >&2
    tail -1 "$LOG" >&2
    echo "Full log: $LOG" >&2
    exit 124
  fi

  sleep 1
  waited=$((waited + 1))
done

wait "$pid" 2>/dev/null
status=$?
set -e

summary="$(grep -m1 "Test run with .* tests" "$LOG" || true)"

if [ -z "$summary" ]; then
  echo >&2
  grep -E "error:" "$LOG" >&2 || true
  echo "No test results were produced. Full log: $LOG" >&2
  exit "$status"
fi

if [ "$stalled" -eq 1 ]; then
  echo "note: tests finished; xcodebuild stalled in simulator teardown and was killed." >&2
fi

case "$summary" in
  *" passed "*)
    echo "$summary"
    echo "==> passed in ${waited}s"
    exit 0
    ;;
esac

echo >&2
grep -E "recorded an issue" "$LOG" >&2 || true
echo "$summary" >&2
echo "Full log: $LOG" >&2
exit 65
