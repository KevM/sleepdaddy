# TestFlight Alpha Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically attach every future Fastlane-uploaded SleepDaddy build to the internal TestFlight group named `Alpha`.

**Architecture:** Keep the existing `ios beta` lane as the single release path. Make Fastlane wait for App Store Connect processing, then use its built-in beta-group association with `distribute_external` left false so `Alpha` is treated as an internal group.

**Tech Stack:** Ruby 3.3, Fastlane 2.237, Fastlane Pilot/Spaceship, Bash, GitHub Actions

## Global Constraints

- The TestFlight group name is exactly `Alpha`.
- `Alpha` is an internal TestFlight group; external beta distribution and TestFlight Beta App Review remain disabled.
- Fastlane Match remains `readonly: true`.
- The application scheme remains `SleepDaddy`.
- The application bundle identifier remains `fm.rodeo.SleepDaddy`.
- Local verification must not upload, redistribute, expire, or otherwise mutate any App Store Connect build.
- Build `1.0.2 (2)` remains a one-time manual group assignment; this automation applies to subsequent uploads.

---

## File Map

- `fastlane/Fastfile`: waits for build processing and assigns the uploaded build to `Alpha`.
- `Scripts/test-release-scripts.sh`: statically guards the internal-group configuration and prevents reintroducing skip-wait behavior.

### Task 1: Assign Processed Builds to the Alpha Internal Group

**Files:**
- Modify: `Scripts/test-release-scripts.sh`
- Modify: `fastlane/Fastfile`

**Interfaces:**
- Consumes: Fastlane `upload_to_testflight(api_key:, groups:)`.
- Produces: `bundle exec fastlane ios beta`, which uploads, waits for processing, and attaches the processed build to internal group `Alpha`.

- [ ] **Step 1: Add the failing Fastlane configuration regression checks**

Append the following checks before the final success message in
`Scripts/test-release-scripts.sh`:

```bash
assert_contains 'INTERNAL_TEST_GROUP = "Alpha"' "$repo_root/fastlane/Fastfile"
assert_contains 'groups: [INTERNAL_TEST_GROUP]' "$repo_root/fastlane/Fastfile"

if grep -Fq 'skip_waiting_for_build_processing: true' \
  "$repo_root/fastlane/Fastfile"; then
  echo "Fastlane beta lane skips processing required for group assignment" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the regression suite and verify it fails**

Run:

```bash
./Scripts/test-release-scripts.sh
```

Expected: FAIL with:

```text
expected 'INTERNAL_TEST_GROUP = "Alpha"' in .../fastlane/Fastfile
```

- [ ] **Step 3: Add the internal group constant**

In `fastlane/Fastfile`, add this constant next to the existing scheme, bundle identifier, and
profile constants:

```ruby
INTERNAL_TEST_GROUP = "Alpha"
```

- [ ] **Step 4: Make TestFlight upload wait and assign Alpha**

Replace:

```ruby
    upload_to_testflight(
      api_key: api_key,
      skip_waiting_for_build_processing: true,
    )
```

with:

```ruby
    upload_to_testflight(
      api_key: api_key,
      groups: [INTERNAL_TEST_GROUP],
    )
```

Do not set `distribute_external`; its false default keeps distribution internal.

- [ ] **Step 5: Run the regression suite and verify it passes**

Run:

```bash
./Scripts/test-release-scripts.sh
```

Expected: PASS with `release script tests passed`.

- [ ] **Step 6: Verify Fastlane parses without performing a release**

Run:

```bash
FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 \
  bundle exec fastlane lanes
```

Expected: exit 0 and an `ios beta` lane. Do not invoke `fastlane ios beta`.

- [ ] **Step 7: Run syntax and focused configuration validation**

Run:

```bash
bash -n Scripts/test-release-scripts.sh
ruby -c fastlane/Fastfile
rg -n 'INTERNAL_TEST_GROUP|groups:|skip_waiting_for_build_processing|distribute_external' \
  fastlane/Fastfile Scripts/test-release-scripts.sh
git diff --check
```

Expected:

- Ruby and Bash syntax checks exit 0.
- `INTERNAL_TEST_GROUP = "Alpha"` and `groups: [INTERNAL_TEST_GROUP]` are present.
- `skip_waiting_for_build_processing: true` is absent from the Fastfile.
- No `distribute_external: true` is introduced.
- `git diff --check` reports no whitespace errors.

- [ ] **Step 8: Commit the implementation**

```bash
git add Scripts/test-release-scripts.sh fastlane/Fastfile
git commit -m "ci: distribute TestFlight builds to Alpha"
```
