# Share Card Redesign

**Date:** 2026-08-02
**Status:** Approved, ready for planning

## Problem

`ShareTimelineCardView` renders the image users export from the night browser. A design
review of a real export found six faults, five of them wasted space and one an outright
formatting bug.

1. **The legend takes two rows.** `ShareTimelineCardView` chunks all six `SleepStage.allCases`
   into rows of three unconditionally. On a typical night two of those chips — "Asleep
   (Unspecified)" and "In Bed" — describe stages that have no data and appear nowhere in the
   chart, and they occupy an entire second row. Worse, the four chips that *do* have data
   restate the left axis, which already prints Awake/REM/Core/Deep in `stage.themeColor`.
2. **The minimap is inert.** The navigator capsule in `CombinedTimelineRail` is a scrubber.
   In a PNG there is nothing to scrub, and its highlighted-versus-grey track actively implies
   an interactivity the image does not have.
3. **A gutter sits above the Awake row.** `SleepTimelineGeometry.topPadding` reserves 16pt to
   clear conflict markers and the top of the In-Bed band. On an export of a night without
   conflicts it is dead space, and it makes the plot vertically lopsided.
4. **The Sources line costs a full row to say nothing.** It renders
   `"Sources: All Sources"` whenever the user has not filtered, which is the common case.
5. **The date range is unreadable.** It renders as
   `"7/31/2026, 10:45 PM – 8/1/2026, 7:17 AM"`.
6. **"Visible Range" is the wrong headline.** It labels the app's pan/zoom viewport — a
   concept the recipient of a shared image does not have — and it occupies the most valuable
   slot on the card. Meanwhile `NightSummary.totalSleepDuration` never appears at all, so the
   card shows stage percentages with no denominator.

Fault 5 is a bug, not a style choice. `AccessibilityHelpers.formattedTimeRange` sets
`dateStyle = .none` on a `DateIntervalFormatter`, but that formatter overrides the request and
includes dates whenever the interval crosses a day boundary. Every overnight sleep session
crosses midnight, so the share card always gets the long form. `IntervalInspectorSheet` calls
the same helper and has the same latent bug for any interval spanning midnight.

## Goals

- Cut the card's wasted vertical space and return it to the chart.
- Lead with total sleep duration, the one number worth sharing.
- Fix `formattedTimeRange` everywhere it is used.
- Leave the in-app timeline rendering exactly as it is today.

## Non-goals

- Changing the on-screen timeline's gutter, minimap, or card surface.
- Untangling the existing duplication where `SleepTimelineCanvas` expresses interactivity as
  both an `isInteractive` init parameter and a `\.timelineInteractionEnabled` environment key.
  It is real, but it is not this change.
- Any reference-image snapshot testing.

## Design

### 1. `TimelineChrome`

A new value type in `SleepDaddy/Layout/SleepTimelineGeometry.swift` carries the difference
between on-screen and export rendering.

```swift
public struct TimelineChrome: Equatable, Sendable {
    public var topPadding: CGFloat
    public var axisHeight: CGFloat
    public var showsNavigator: Bool
    public var showsCardSurface: Bool

    public static let interactive = TimelineChrome(
        topPadding: SleepTimelineGeometry.topPadding,
        axisHeight: SleepTimelineGeometry.timeAxisHeight,
        showsNavigator: true,
        showsCardSurface: true
    )

    public static let export = TimelineChrome(
        topPadding: 4,
        axisHeight: SleepTimelineGeometry.timeLabelBandHeight,
        showsNavigator: false,
        showsCardSurface: false
    )
}
```

`.interactive` is defined in terms of the existing statics so there is a single source of
truth and the constants pinned in `SleepTimelineGeometryTests` continue to hold.

`SleepTimelineGeometry`, `SleepTimelineCanvas`, `CombinedTimelineRail` and
`SleepTimelineCanvasVerticalLayout` each gain a `chrome` parameter defaulting to
`.interactive`. All existing construction sites — 33 across 5 files — compile unchanged.

A plain value threaded through initializers is preferred over an environment key because
`SleepTimelineGeometry` is a `Sendable` struct rather than a `View` and cannot read the
environment; an environment-based design would require the canvas to extract the value and
hand it to the geometry anyway, while making the layout depend on ambient state that geometry
tests cannot set.

### 2. What the chrome changes

**`SleepTimelineGeometry`** — `usablePlotHeight()` and `yCenterPosition(for:displayedStages:)`
read `chrome.topPadding` and `chrome.axisHeight` in place of `Self.topPadding` and
`Self.timeAxisHeight`.

**`CombinedTimelineRail`** — the outer `.frame(height:)` uses `chrome.axisHeight`. The
`navigator(geometry:layout:)` capsule renders only when `chrome.showsNavigator`; when it does
not, the time-label band takes the full rail height. `CombinedTimelineRailLayout` takes the
rail height so `railBounds` stays correct.

**`SleepTimelineCanvas`** — `SleepTimelineCanvasVerticalLayout.plotHeight` subtracts
`chrome.axisHeight`. The In-Bed band's `bandY` uses `chrome.topPadding`. The
`.background` / `.clipShape` / `.shadow` modifiers apply only when `chrome.showsCardSurface`,
which removes the nested card-inside-a-card on export.

**Expected vertical arithmetic** at the card's 240pt canvas height:

| | interactive | export |
|---|---|---|
| `usablePlotHeight` | 240 − 16 − 44 = 180 | 240 − 4 − 20 = 216 |
| lane height | 45 | 54 |
| plot region height | 240 − 44 = 196 | 240 − 20 = 220 |
| space above Awake centerline | 38.5 | 31 |
| space below Deep centerline | 22.5 | 27 |

Only 16pt of the perceived gutter was ever `topPadding`; the remainder is inherent to
centering four stages in evenly divided lanes and cannot be removed without clipping the
stroke. The visual fix is therefore symmetry rather than removal — 31 against 27 reads as
intentional margin where 38.5 against 22.5 reads as a gutter.

### 3. Card layout

```
SleepDaddy                          caption, bold, accent
7h 51m asleep                       title, bold — the hero
Fri, Jul 31, 2026 · 10:45 PM – 7:17 AM   caption2, secondary
Sources: Apple Watch                only when a filter is applied
────────────────────────────────
timeline canvas (chrome: .export)
────────────────────────────────    only when the legend below is non-empty
■ Asleep (Unspecified)  ■ In Bed    only stages the axis cannot label
```

The duration string comes from
`AccessibilityHelpers.formattedTimeInterval(night.summary.totalSleepDuration)`, which already
produces the `"7h 51m"` form.

`ShareTimelineCardView.sourceFilterDescription` changes from `String` to `String?`.
`ContentView.exportAndShare(night:)` passes `nil` when `selectedSourceIdentifiers.isEmpty`
instead of synthesising `"All Sources"`, which keeps the view from having to know what
"unfiltered" means. `SleepShareRenderer.renderShareImage` forwards the optional unchanged.

The first `Divider()` is unconditional. The second renders only alongside a non-empty legend.

### 4. Two pure functions

Both live alongside the card and are unit-tested directly.

```swift
/// Stages present in the night that the left axis does not already label.
/// Result is always a subset of {.asleepUnspecified, .inBed}.
static func legendStages(for night: AssembledNight) -> [SleepStage]
```

The implementation must consult both collections: `.inBed` intervals live in
`night.rawIntervals` (this is what `SleepTimelineCanvas` filters when drawing the background
band) while `.asleepUnspecified` lives in `night.displayLaneIntervals`. It then subtracts
`SleepTimelineGeometry.defaultDisplayedStages`. Because the result can contain at most two
stages, a second legend row is structurally impossible rather than merely unlikely.

```swift
/// "Fri, Jul 31, 2026".
static func formattedDateHeader(
    _ date: Date, calendar: Calendar = .current, locale: Locale = .current
) -> String
```

This replaces the existing `.full` `DateFormatter` style, which produced
`"Friday, July 31, 2026"` and cost the card most of a line. Abbreviating the weekday and month
recovers that width; the year stays, because a shared image outlives the moment it was taken
and the reader has no other cue for which year the night belongs to. The injected `calendar`
and `locale` exist so the output is testable without depending on the device's settings.

### 5. Time formatting

`CombinedTimelineRail.formattedTime(_:locale:timeZone:)` already formats a clock time
correctly using `Date.FormatStyle(date: .omitted, time: .shortened)`. Move it to
`AccessibilityHelpers` as `formattedClockTime(_:locale:timeZone:)`, have `CombinedTimelineRail`
call it there, and rebuild the range helper on top of it:

```swift
public static func formattedTimeRange(
    start: Date, end: Date,
    locale: Locale = .current, timeZone: TimeZone = .current
) -> String {
    let from = formattedClockTime(start, locale: locale, timeZone: timeZone)
    let to = formattedClockTime(end, locale: locale, timeZone: timeZone)
    return "\(from) – \(to)"
}
```

The separator is an en dash, matching what the card mockup and the existing helper produced.
`DateIntervalFormatter` is removed from the codebase. Because `IntervalInspectorSheet` calls
the same helper, it is fixed by the same change.

## Testing

Follows the composition-test style documented at the top of `SnapshotTests.swift`: assert that
a view assembles its fixture and rasterizes at its intended size, never that it matches a
reference PNG.

**Geometry** (`SleepTimelineGeometryTests`)
- `usablePlotHeight()` and `yCenterPosition(for:)` produce the interactive-chrome values the
  suite already asserts when `chrome` is defaulted.
- Under `.export` at a 240pt canvas, the space above the Awake centerline and below the Deep
  centerline agree within 5pt.

**Content** (new `ShareCardContentTests`)
- `legendStages(for:)` across four fixture nights: neither extra stage present, unspecified
  only, in-bed only, both. Expected results `[]`, `[.asleepUnspecified]`, `[.inBed]`,
  `[.asleepUnspecified, .inBed]`. The two-stage case pins the ordering, which follows
  `SleepStage.allCases`.
- `formattedDateHeader` renders `"Fri, Jul 31, 2026"` under an injected `en_US` locale and
  fixed time zone, and keeps the correct year for a night in a previous year.
- `formattedTimeRange` for a 10:45 PM → 7:17 AM pair crossing midnight returns exactly
  `"10:45 PM – 7:17 AM"` under an injected `en_US` locale and fixed time zone. This is the
  regression lock for the `DateIntervalFormatter` bug; asserting the full string rather than
  the absence of a date is what makes it unambiguous.

**Composition** (`SnapshotTests`)
- `CombinedTimelineRail` under `.export` rasterizes at 20pt tall, not 44pt.
- `ShareTimelineCardView` rasterizes non-zero with a filter applied and with `nil`.

**Existing tests to update**
- `ShareRendererTests` passes `sourceFilterDescription: "Apple Watch"`; it still compiles
  against `String?` but should gain a `nil` case.

**Preview**
- A `ShareTimelineCardView` preview backed by fixture data, so the card can be inspected
  without going through the share sheet.

## Risks

- Threading `chrome` through four initializers touches files the main screen depends on. The
  `.interactive` default is what keeps that safe; any call site that fails to compile is a site
  that was relying on a static the change intends to parameterize.
- The header line now carries date, year and clock range in one `caption2` run
  (`"Fri, Jul 31, 2026 · 10:45 PM – 7:17 AM"`). At the card's fixed 540pt width this fits
  comfortably, but a long locale format could wrap it. The card should be checked in the
  preview under at least one non-`en_US` locale before release.
