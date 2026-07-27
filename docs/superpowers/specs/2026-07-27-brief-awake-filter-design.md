# Brief Awake Filter

## Problem

Some sleep trackers emit a large number of one-minute awake samples across a night. On the
timeline each one becomes a spike out of the sleep rows and back, and a night carrying dozens
of them reads as noise rather than as sleep architecture. The intervals are real HealthKit
records, so excluding them one at a time through the existing local-exclusion mechanism is
impractical at that volume.

The existing filter mechanism has two stages, both applied to raw intervals before assembly in
`NightAssembler`: source selection and local sample exclusions. Both feed `summary`, so both
change the reported sleep and awake totals. Neither is the right layer for this problem, which
is about visual density rather than data eligibility.

## Design

Brief awakes are hidden from the timeline drawing only. Every reported number — total sleep,
awake duration, in-bed duration, stage durations, stage percentages — continues to be computed
from the unfiltered primary lane and is unaffected by the filter. The app keeps telling the
truth about what HealthKit recorded; it just stops drawing the spikes that carry no shape.

An awake interval is brief when its duration is 60 seconds or less. A 61-second awake and a
two-minute awake are still drawn. The threshold is a constant, not a user-facing value: the
control is a single on/off toggle.

The filter is off by default, so no existing timeline changes appearance until the toggle is
switched on.

Deleting a brief awake from the lane is not sufficient on its own. `stepSegments` emits the
vertical connector between two intervals only when they touch in time within a millisecond
(`SleepTimelineGeometry.swift:337`), so a removed spike would leave both a one-minute
horizontal hole and two missing connectors — a visible break in the path rather than the
smooth line the filter is meant to produce. The time a hidden spike occupied is therefore
reassigned to its neighbour in the lane, and the drawn path stays continuous across it.

### Where the filtering happens

Smoothing runs in `NightAssembler`, after `primaryLane` and `summary` have been computed, and
produces a second lane stored alongside the first. Placing it there makes the guarantee
structural rather than a matter of discipline: `summary` is calculated before the smoother
runs and cannot observe its output.

The two alternatives were rejected. Filtering inside `SleepTimelineCanvas` at draw time would
leave the logic testable only by rendering pixels, and hit-testing would continue to see
hidden spikes, so a tap on empty track could open an inspector for an invisible interval.
Filtering alongside the source and exclusion filters on raw intervals would feed `summary` and
silently reduce the reported awake total, which is the outcome this design exists to avoid.

## Component Changes

### `AwakeSpikeSmoother.swift` (new, `Services/`)

A pure value type exposing `smooth(lane: [NormalizedSleepInterval]) -> [NormalizedSleepInterval]`
and the constant `briefAwakeThreshold: TimeInterval = 60`.

An interval is hidden when `stage == .awake` and `duration <= briefAwakeThreshold`. The lane is
assumed sorted by `startDate` and contiguous, which is what `resolvePrimaryLaneAndConflicts`
produces.

The pass works as follows:

- If every interval in the lane is hidden, the lane is returned unchanged. This covers the
  degenerate night consisting of nothing but brief awakes, where smoothing would otherwise
  yield an empty timeline while the summary still reported awake time.
- Otherwise each hidden interval is dropped and its span is absorbed by the preceding kept
  interval, whose `endDate` extends to the hidden interval's `endDate`.
- A hidden interval with no preceding kept interval — one at the head of the lane — is instead
  absorbed by the following kept interval, whose `startDate` extends back to the hidden
  interval's `startDate`.
- Kept intervals that touch in time after absorption and share both `stage` and
  `sourceIdentifier` are then coalesced into one, matching the rule already used when the
  primary lane is built (`NightAssembler.swift:198`).

An extended or coalesced interval keeps the identity of the interval that absorbed the span,
so lane identifiers stay stable and selection continues to resolve.

The smoother does not consider `inBed`. Where an `inBed` interval is the neighbour of a hidden
spike it absorbs the span like any other stage; `stepSegments` filters `inBed` out of the
drawn path independently, and the In Bed background band is drawn from `rawIntervals` and is
untouched.

### `SleepPreferences`

Gains `hidesBriefAwakes: Bool`, defaulting to `false` in the memberwise initialiser.

The type needs an explicit `init(from:)` that reads the new key with `decodeIfPresent` and
falls back to `false`. Swift's synthesized `Codable` conformance does not apply default
property values to missing keys, and `PreferencesStore.load()` discards decode errors with
`try?` and returns `.default` (`PreferencesStore.swift:12`). Without the custom initialiser,
adding a field would silently reset every stored preference — core window, source selection,
and the full exclusion list — the first time an existing install decoded its saved
preferences. Encoding stays synthesized.

### `AssembledNight`

Gains `displayLaneIntervals: [NormalizedSleepInterval]`, the lane the canvas draws. When the
preference is off it is identical to `primaryLaneIntervals`.

`NightAssembler.assembleNight` populates it by passing `primaryLane` through the smoother when
`preferences.hidesBriefAwakes` is set, and by passing `primaryLane` through unchanged
otherwise. Both early-return paths for nights without sleep data pass an empty array.

`summary`, `rawIntervals`, `conflicts`, `detectedStart`, and `detectedEnd` are all computed
before this step and are unchanged by it. In particular the night's bounds cannot move when
the toggle flips, which the viewport handling below relies on.

### `SleepTimelineCanvas`

Five reads of `night.primaryLaneIntervals` move to `night.displayLaneIntervals`: the
`asleepUnspecified` band pass (line 167), the `stepSegments` call (line 174), the selected
segment emphasis lookup (line 198), the tap hit-test (line 326), and the VoiceOver
chronological interval list (line 334).

Moving the last two together with the drawing means a hidden spike cannot be tapped, cannot be
opened in the inspector, and is not announced by VoiceOver. The visual, touch, and
accessibility representations of the timeline stay in agreement.

`ShareTimelineCardView` renders the same canvas and follows with no change of its own, so an
exported image matches what was on screen.

### `NightBrowserModel`

Gains `toggleHideBriefAwakes()`, which flips `preferences.hidesBriefAwakes`, saves through
`PreferencesStore`, clears `selectedInterval`, and reassembles.

`selectedInterval` is cleared because a selection made before the toggle may name an interval
that no longer exists in the display lane, which would leave the inspector sheet open over a
segment the canvas can no longer emphasise.

`reassembleNights()` gains a `preservingViewport: Bool = false` parameter and skips the
trailing `resetViewportToSelectedNight()` when it is set; the toggle passes `true`. Every
existing caller keeps its current behaviour. The distinction is that source selection,
exclusions, and the core window all change `detectedStart` and `detectedEnd`, so the viewport
has to be re-derived, whereas this toggle provably cannot move the night's bounds. Resetting
zoom and pan on a display-only toggle would throw away the user's position on the timeline for
no reason.

### `CompactSourceFilterButton`

A "Timeline Display" section is added above the existing "Sources" section in the filter
sheet, holding a single `Toggle` labelled "Hide Brief Awakes" with the footer: "Awake periods
of one minute or less are hidden from the timeline. Sleep totals are unaffected."

The view takes two new members, `hidesBriefAwakes: Bool` and `onToggleHideBriefAwakes: () -> Void`,
supplied by `ContentView` from the model.

The button's blue active-filter dot currently appears when `selectedSourceIDs` is non-empty
(line 32). Its condition widens to include `hidesBriefAwakes`, so a timeline hiding data
always advertises that a filter is active. "Clear Filter" continues to clear source selection
only; it is inside the Sources section and the toggle has its own affordance.

## Accepted Trade-off

With the toggle on, the Awake row can report a percentage larger than the visible spikes
suggest, because the percentage is computed from the summary and the summary ignores the
filter. This follows directly from the decision to keep the numbers truthful to HealthKit. The
footer under the toggle is what reconciles the two for the reader.

## Testing

New `AwakeSpikeSmootherTests`:

- A 60-second awake between two Core intervals is removed and the neighbours join into a
  single Core interval covering the whole span.
- A 61-second awake and a two-minute awake are both kept, confirming the boundary.
- A brief awake between Core and REM is removed, the preceding Core extends to its end, and
  the two intervals remain distinct so the step lands at the spike's end.
- A brief awake at the head of the lane is absorbed backwards by the following interval, whose
  `startDate` moves to the spike's start.
- A brief awake at the tail of the lane is absorbed by the preceding interval.
- Two brief awakes separated by a short Core interval are both removed in one pass.
- A lane consisting only of brief awakes is returned unchanged.
- The smoothed lane covers exactly the same total span as the input in every case above.
- Neighbours from different sources that share a stage are left as separate touching
  intervals rather than coalesced.

New `NightAssemblerTests` cases:

- With `hidesBriefAwakes` on, `summary` is equal to the summary produced with it off for the
  same input.
- With `hidesBriefAwakes` off, `displayLaneIntervals` equals `primaryLaneIntervals`.
- `detectedStart` and `detectedEnd` are equal with the toggle on and off.

New `SleepPreferencesTests` case:

- Decoding a JSON payload written before the field existed yields the stored core window,
  source selection, and exclusions intact, with `hidesBriefAwakes` false.

New snapshot test: a night containing several brief awake spikes rendered with the toggle on,
as a new reference PNG. Existing snapshot references are unaffected, because the preference
defaults to off and the display lane is then identical to the primary lane.
