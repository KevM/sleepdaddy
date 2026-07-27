# Stage Percentage Labels

## Problem

The sleep viewer shows how the night was shaped but never how it was divided. The header
reports one number, total sleep duration, and `SleepTimelineCanvas` draws four labelled stage
rows: Awake, REM, Core, Deep. Reading the proportion of the night spent in each stage means
eyeballing the relative length of the stepped path in each row.

`NightSummary` already carries `stageDurations`, so the underlying figures exist and are
simply never presented.

## Design

Each stage row label in the chart gains the stage's share of the night as a second line
beneath the stage name. The values describe the whole night and do not change as the chart is
zoomed or panned, which keeps them stable during gestures and consistent with the total
duration in the header.

The denominator is the sum of the four labelled stages: Awake, REM, Core, Deep. The four
displayed percentages therefore always sum to exactly 100%. `asleepUnspecified` and `inBed`
are excluded from the denominator; neither owns a stage row, so neither can carry a label, and
including them would leave the visible column summing to less than 100% with no indication of
where the remainder went.

When the denominator is zero, no percentages are shown at all. This is the case for a night
recorded entirely as unspecified sleep, common with basic trackers, where the alternative
would be four rows reading `0%`.

Percentages are whole numbers. Rounding each value independently would leave the column
summing to 99% or 101% for many nights, so the largest-remainder method is used: each value is
floored, then the leftover points are distributed to the largest fractional remainders. Ties
are broken by `SleepStage.rowIndex` so the output is deterministic.

The calculation runs on whole seconds as integers rather than on percentages as `Double`s. In
floating point a true 27.5% evaluates to 27.500000000000004, so an exact tie between
remainders is unrepresentable and rounding noise decides which stage receives a leftover
point. Integer division and modulo make both the comparison and the tie-break exact.

## Component Changes

### `NightSummary+StagePercentages.swift` (new)

An extension on `NightSummary` exposing `stagePercentages: [SleepStage: Int]`.

- Considers `[.awake, .rem, .core, .deep]`, reading each from `stageDurations` and treating a
  missing key as zero duration.
- Returns an empty dictionary when the sum of those four durations is not greater than zero.
- Otherwise returns whole-number percentages summing to exactly 100, by the largest-remainder
  method described above.

A stage with a small but nonzero duration may render `0%`. This is accepted: the stage row
still shows its intervals, and forcing a floor of 1% would break the guarantee that the
column sums to 100.

The extension is a pure function of the summary, which keeps it testable without constructing
a view and lets both the app and the share card read it from the `AssembledNight` they
already hold.

### `SleepTimelineCanvas`

The fixed leading label column becomes a two-line block per stage: the stage name with its
existing treatment, over the percentage in `.caption2` semibold, `.secondary`, with
`.monospacedDigit()` so the numbers do not shift width between nights.

The block keeps the current `.position(x:y:)` placement, so it stays vertically centred on its
row and the plot geometry, stepped path, and canvas drawing are untouched. When
`stagePercentages` is empty the second line is omitted and the column renders exactly as it
does today.

`ShareTimelineCardView` renders the same canvas and picks up the labels with no change of its
own.

## Dynamic Type

Row height is `(canvasHeight - topPadding - timeAxisHeight) / 4`, roughly 49pt on the detail
screen. Two lines of `.caption2` fit comfortably at normal sizes but overflow into the
neighbouring row at accessibility sizes.

The label column is constrained with `.dynamicTypeSize(...(.accessibility1))`, and each line
uses `lineLimit(1)` with `minimumScaleFactor(0.8)`, keeping the block inside its row. The
constraint applies to the label column only; the rest of the view scales normally.

## Accessibility

Each label block is collapsed into a single element with `.accessibilityElement(children:
.ignore)` and an explicit label of the form "Deep, 23 percent of night", so VoiceOver reads it
as one unit rather than as two disconnected fragments. When no percentages are available the
label is the stage name alone.

The chronological interval list that carries the primary VoiceOver experience is unaffected.

## Testing

New unit tests for `stagePercentages`:

- The four values sum to exactly 100 across a range of inputs.
- Four equal durations yield 25/25/25/25.
- An input where independent rounding would total 101 still sums to 100.
- Unspecified sleep is excluded from the denominator.
- A night recorded entirely as unspecified sleep returns an empty dictionary.
- Equal fractional remainders are broken by row order, so repeated runs agree.

Existing snapshot references change and are regenerated by deleting the affected PNGs and
re-running the suite: `timeline_canvas_snapshot`, `share_card_snapshot`,
`snapshot_portrait_light`, `snapshot_portrait_dark`, `snapshot_landscape`,
`snapshot_dynamic_type`, and `snapshot_reduce_motion`.
