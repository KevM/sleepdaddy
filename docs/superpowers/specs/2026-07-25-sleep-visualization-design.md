# SleepDaddy Sleep Visualization Design

## Summary

SleepDaddy is a read-only iOS application for inspecting HealthKit sleep data at
greater detail than Apple Health currently allows. Its primary experience is a
zoomable, pannable sleep-stage timeline supported by multi-night navigation,
explicit source filtering, local record exclusions, adaptive sleep boundaries,
and current-view image sharing.

The first release is deliberately local and focused. It does not write to
HealthKit, require an account, contact a server, or provide long-term trend
analysis.

## Goals

- Make individual sleep-stage intervals readable through horizontal zooming and
  panning.
- Make nearby nights quick to browse from a compact overview strip.
- Let the user select which HealthKit data sources contribute to the timeline.
- Prevent unusual naps or bad records from skewing nightly totals.
- Include contiguous sleep that falls slightly outside the configured night
  window.
- Export the currently visible timeline as a clean image that is easy to copy,
  paste, save, or share.
- Preserve all HealthKit records unchanged.

## Non-Goals for Version 1

- Writing, editing, or deleting HealthKit data.
- Cloud sync, accounts, analytics, or network services.
- Long-term trend charts or sleep coaching.
- Automatic medical interpretation or health recommendations.
- A fully configurable share-card designer.
- Exporting an entire night independently of the current viewport.

## Platform and Project Conventions

The app follows the conventions used by the KevCalc reference project:

- Native SwiftUI application.
- Swift 6.
- iOS 26 minimum deployment target.
- XcodeGen project definition in `project.yml`.
- Generated Xcode project and generated `Info.plist` are not committed.
- Swift Testing for unit tests.
- iPhone 17 simulator as the default local build and test destination.
- Bundle identifier prefix `fm.rodeo`.
- Small types with isolated responsibilities.

HealthKit behavior that requires real personal data will be verified on a
physical iPhone. Simulator tests and previews use fixture data.

## Architecture

### HealthKitSleepStore

`HealthKitSleepStore` requests read-only authorization for sleep analysis and
fetches raw `HKCategorySample` records over a requested date interval. It is the
only component that imports and talks directly to HealthKit.

The store conforms to a protocol so tests and SwiftUI previews can substitute a
fixture-backed implementation.

### SleepNormalizer

`SleepNormalizer` converts raw samples into application-owned sleep intervals.
Each normalized interval retains:

- Stable HealthKit sample identifier.
- Start and end times.
- Stage: awake, core, deep, REM, in bed, or asleep unspecified.
- Source name and source identifier.
- HealthKit provenance needed for conflict inspection.

Legacy generic-asleep values map to asleep unspecified. The normalizer preserves
overlaps rather than silently dropping them because HealthKit can legitimately
contain an in-bed interval overlapping detailed stage intervals.

### SleepPreferences

`SleepPreferences` stores only application choices:

- Core night-window start and end.
- Persistent source selection.
- Locally excluded HealthKit sample identifiers.

It does not copy or persist the underlying sleep records. Version 1 uses a
lightweight local preferences store appropriate for these small values.

### NightAssembler

`NightAssembler` applies source filtering and local exclusions, groups normalized
intervals around each core night window, detects contiguous boundary extensions,
and calculates display summaries.

The default core window runs from 7:00 PM on the labeled date through 7:00 AM the
following morning. The user may change these times in Settings.

### NightBrowserModel

`NightBrowserModel` coordinates authorization state, buffered data loading,
night selection, source filters, exclusions, summaries, the timeline viewport,
and image sharing. It exposes view-ready state but contains no drawing code.

### SleepTimelineCanvas

`SleepTimelineCanvas` is a custom SwiftUI `Canvas` visualization. A separate
geometry component converts dates and stages into positions so interval layout,
viewport clamping, and navigator synchronization can be unit tested without
rendering pixels.

The timeline supports:

- Horizontal pinch to zoom.
- Horizontal drag to pan.
- A slim context navigator showing the visible range.
- Coarse jumps by interacting with the navigator.
- A Reset control that restores the detected full-night range.
- Segment selection for detailed inspection.

### SleepShareRenderer

`SleepShareRenderer` builds a dedicated SwiftUI share view from the selected
night and current viewport. SwiftUI `ImageRenderer` creates a raster image, which
is passed to the standard iOS share sheet.

The export is a newly rendered image, not a screenshot of application chrome.

## Adaptive Night Boundaries

The configured 7:00 PM–7:00 AM window is a core window, not a hard clipping
boundary.

For each night:

1. Fetch candidate records from the core window plus a four-hour buffer on both
   sides.
2. Apply the active source filter.
3. Remove locally excluded records.
4. Seed the night with eligible sleep records overlapping the core window.
5. Expand backward and forward while eligible intervals remain contiguous.
6. Treat gaps of 30 minutes or less as contiguous.
7. Stop at a gap greater than 30 minutes or at the four-hour safety cap.

This includes a sleep session that begins at 6:00 PM and continues into the core
window while keeping a disconnected midday nap out of the night. Changing
sources or exclusions reruns boundary detection, because those choices may alter
continuity.

If no eligible sleep record overlaps the core window, the date remains
navigable but displays an empty-night state. A disconnected record is not
promoted into the night merely because it falls inside the outer buffer.

The navigator distinguishes the configured core window from any detected
extension so the user can understand why extra time is included.

## Main Experience

The app opens to the most recent night with eligible sleep data.

### Multi-Night Overview

A horizontally scrollable strip presents nearby nights. Each populated night
shows its total sleep duration and a compact stage summary. Empty nights remain
visible. Tapping a night selects it, and horizontal navigation moves between
adjacent nights.

Long-term trend analysis is deferred, but the strip provides enough context to
spot gaps and move quickly among nights.

### Selected-Night Detail

The selected-night screen contains:

- Night date and summary.
- Persistent source-filter control.
- Zoomable detailed timeline.
- Slim context navigator.
- Reset and Share actions.
- Inspector access for individual records.

The source filter persists across nights. The user may select one or multiple
HealthKit sources. Refiltering recomputes boundaries, totals, conflicts, and the
viewport locally.

### Record Inspection and Exclusion

Selecting a timeline segment displays:

- Sleep stage.
- Exact start and end times.
- Duration.
- HealthKit source.
- Conflict indication when overlapping selected sources disagree.

The inspector can exclude that HealthKit sample from SleepDaddy. Exclusion is
local, persists between launches, and never modifies HealthKit. An Excluded
Records screen lists saved exclusions and allows them to be restored.

## Timeline Conflict Handling

Detailed stages from a single well-formed source normally do not overlap, but
records from multiple selected sources may conflict.

The application preserves all selected provenance. For the primary visual lane,
it resolves conflicting detailed stages deterministically using these rules:

1. Prefer a specific stage (awake, core, deep, or REM) over asleep unspecified.
2. Prefer a detailed stage over an in-bed interval.
3. If equally specific selected sources disagree, use a stable source ordering
   derived from the user's source-selection order.

The inspector identifies the conflict and lists all contributing records so the
resolution is never silent. Changing source selection or excluding a record
immediately recomputes the lane.

## Image Sharing

Version 1 shares the current timeline viewport only.

The generated image contains:

- The night date.
- Exact visible time range.
- Active source-filter description.
- The visible sleep-stage timeline.
- Stage legend.

It omits:

- Application controls and navigation.
- Personal identifiers.
- Full-night totals that could be misread as totals for the visible partial
  range.

After rendering, the standard iOS share sheet allows the image to be copied,
pasted, saved, or sent through installed applications. If rendering fails, the
current screen and viewport remain unchanged and the app presents a retryable
error.

## Authorization, Empty States, and Errors

SleepDaddy requests read-only access to HealthKit sleep-analysis samples.

The UI explicitly handles:

- HealthKit unavailable on the device.
- Authorization that does not yield readable data.
- No sleep records for a selected night.
- Unsupported or legacy sleep categories.
- Conflicting records from selected sources.
- Share-image rendering failure.

Because HealthKit protects the user's authorization choices, the app does not
claim to distinguish a denial from an empty readable dataset when the framework
does not expose that distinction. Instead, it presents neutral setup guidance.

## Privacy

- HealthKit is read-only.
- Sleep records remain on device and are not copied into an application
  database.
- No account, server, analytics SDK, or network access is included.
- Locally persisted values are limited to settings, source identifiers, and
  excluded sample identifiers.
- A share image leaves the app only after an explicit Share action and selection
  through the system share sheet.

## Accessibility

The visualization does not rely on color alone. Stage rows use labels and a
consistent vertical position in addition to color.

Each displayed interval has an accessible description containing stage, start
time, end time, duration, and source. VoiceOver users can move through intervals
in chronological order without performing pinch or pan gestures. Reset, Share,
source selection, exclusion, and navigator controls have explicit accessibility
labels and values.

## Data Flow

1. The app requests HealthKit read access.
2. `NightBrowserModel` asks `HealthKitSleepStore` for a buffered range covering
   the visible overview dates.
3. `SleepNormalizer` converts raw samples and preserves provenance.
4. `NightAssembler` applies the source selection and exclusions, then computes
   adaptive boundaries and summaries.
5. The overview and selected-night UI render view-ready models.
6. Timeline gestures update only viewport state.
7. Source or exclusion changes recompute assembled nights from the in-memory
   normalized records.
8. Share renders the current view-ready data and viewport into an image.

## Testing and Verification

Swift Testing unit suites use fixture-backed sleep stores and cover:

- Standard and cross-midnight grouping.
- Early sleep extending from 6:00 PM into the 7:00 PM core window.
- Late sleep extending beyond 7:00 AM.
- Gaps exactly at, below, and above the 30-minute continuity threshold.
- The four-hour extension cap.
- Disconnected midday naps.
- Empty core windows.
- Multiple selected sources and overlapping records.
- Deterministic conflict resolution.
- Persistent filters and exclusions.
- Legacy and unspecified sleep categories.
- Timeline coordinate calculations.
- Viewport clamping, pinch scaling, panning, reset, and navigator
  synchronization.
- Share context matching the active night, visible time range, and source
  selection.

A small image-snapshot suite protects the timeline and share-card composition
from accidental visual regressions. Snapshot fixtures use fixed locale, time
zone, color scheme, scale, and dimensions.

Manual verification covers:

- HealthKit authorization and real sleep data on a physical iPhone.
- Source names and filtering with real HealthKit provenance.
- Pinch, pan, navigator, and Reset interaction feel.
- Dynamic Type, VoiceOver, contrast, and non-color stage recognition.
- Copying and pasting the exported image into Messages and Notes.
- An iPhone 17 simulator build and unit-test run with code signing disabled.

## Version 1 Success Criteria

The first release is successful when a user can:

1. Grant read-only HealthKit access.
2. Navigate among nearby nights.
3. Select the HealthKit sources they trust.
4. See contiguous sleep slightly outside the configured window without pulling
   in a disconnected midday nap.
5. Exclude a suspicious record and have that exclusion persist.
6. Pinch and pan far enough to inspect short sleep-stage intervals.
7. Tap an interval to see exact time, duration, stage, source, and conflicts.
8. Export the current viewport with useful context and paste the image into
   another application.
