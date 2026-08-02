# Share Card Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the exported share image so it leads with total sleep duration, drops the inert minimap, the redundant legend rows, the top gutter and the "All Sources" line — while leaving the on-screen timeline pixel-identical.

**Architecture:** A new `TimelineChrome` value type carries the difference between on-screen and export rendering. `SleepTimelineGeometry`, `SleepTimelineCanvas`, `CombinedTimelineRail` and `SleepTimelineCanvasVerticalLayout` each take one, defaulting to `.interactive`, so every existing call site compiles untouched and only `ShareTimelineCardView` opts into `.export`. Two pure functions — one selecting legend stages, one formatting the date header — are unit-tested directly rather than through rendering.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen, `ImageRenderer` for export.

**Spec:** `docs/superpowers/specs/2026-08-02-share-card-redesign-design.md`

**Build/test commands** (from `AGENTS.md`):

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Single-test form used throughout this plan:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SuiteName/testName
```

No new files are added to the Xcode project except test files under `SleepDaddyTests/`, which `project.yml` picks up by directory. `xcodegen generate` must be run after creating `SleepDaddyTests/ShareCardContentTests.swift` in Task 6.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `SleepDaddy/Layout/SleepTimelineGeometry.swift` | Timeline layout math; now also owns `TimelineChrome` | Modify |
| `SleepDaddy/Utilities/AccessibilityHelpers.swift` | Shared date/time/duration string formatting | Modify |
| `SleepDaddy/Views/CombinedTimelineRail.swift` | Time-label band + navigator scrubber | Modify |
| `SleepDaddy/Views/SleepTimelineCanvas.swift` | The drawn timeline plot and its surface | Modify |
| `SleepDaddy/Views/ShareTimelineCardView.swift` | The exported card's composition and legend rule | Modify |
| `SleepDaddy/Utilities/SleepShareRenderer.swift` | `ImageRenderer` wrapper | Modify |
| `SleepDaddy/Views/ContentView.swift` | Supplies the source-filter description | Modify |
| `SleepDaddyTests/SleepTimelineGeometryTests.swift` | Geometry assertions under both chromes | Modify |
| `SleepDaddyTests/CombinedTimelineRailTests.swift` | Locale-aware clock formatting | Modify |
| `SleepDaddyTests/SnapshotTests.swift` | Composition tests (no reference PNGs) | Modify |
| `SleepDaddyTests/ShareRendererTests.swift` | Renderer smoke tests | Modify |
| `SleepDaddyTests/ShareCardContentTests.swift` | Legend rule + header/range formatting | Create |

`TimelineChrome` lives in `SleepTimelineGeometry.swift` rather than its own file because it exists only to parameterize that file's layout math, and `.interactive` is defined in terms of the statics declared there — splitting them would separate two things that must change together.

---

## Task 1: Fix `formattedTimeRange`

`AccessibilityHelpers.formattedTimeRange` sets `dateStyle = .none` on a `DateIntervalFormatter`, but that formatter overrides the request and includes full calendar dates whenever the interval crosses a day boundary. Every overnight sleep session crosses midnight, so the share card always renders `"7/31/2026, 10:45 PM – 8/1/2026, 7:17 AM"`. `IntervalInspectorSheet` calls the same helper and has the same bug.

`CombinedTimelineRail` already formats a clock time correctly. This task hoists that implementation into `AccessibilityHelpers` and rebuilds the range on top of it, so there is one clock formatter in the codebase.

**Files:**
- Modify: `SleepDaddy/Utilities/AccessibilityHelpers.swift:25-30`
- Modify: `SleepDaddy/Views/CombinedTimelineRail.swift:264-281`
- Modify: `SleepDaddyTests/CombinedTimelineRailTests.swift:10-19`
- Create: `SleepDaddyTests/ShareCardContentTests.swift`

- [ ] **Step 1: Write the failing test**

Create `SleepDaddyTests/ShareCardContentTests.swift`:

```swift
import Foundation
import Testing
@testable import SleepDaddy

struct ShareCardContentTests {
    private static let utc = TimeZone(secondsFromGMT: 0)!

    private static func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute
            )
        )!
    }

    /// Regression lock for the `DateIntervalFormatter` fault: it ignored `dateStyle = .none`
    /// and printed both calendar dates for any range crossing midnight.
    @Test func timeRangeCrossingMidnightPrintsOnlyClockTimes() {
        let start = Self.date(year: 2026, month: 7, day: 31, hour: 22, minute: 45)
        let end = Self.date(year: 2026, month: 8, day: 1, hour: 7, minute: 17)

        let formatted = AccessibilityHelpers.formattedTimeRange(
            start: start,
            end: end,
            locale: Locale(identifier: "en_US"),
            timeZone: Self.utc
        )

        #expect(formatted == "10:45 PM – 7:17 AM")
    }

    @Test func clockTimeHonorsLocaleHourCycle() {
        let noon = Self.date(year: 2026, month: 7, day: 31, hour: 12, minute: 5)

        let us = AccessibilityHelpers.formattedClockTime(
            noon, locale: Locale(identifier: "en_US"), timeZone: Self.utc
        )
        let uk = AccessibilityHelpers.formattedClockTime(
            noon, locale: Locale(identifier: "en_GB"), timeZone: Self.utc
        )

        #expect(us == "12:05 PM")
        #expect(uk == "12:05")
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareCardContentTests
```

Expected: compile failure — `type 'AccessibilityHelpers' has no member 'formattedClockTime'`, and `formattedTimeRange` has no `locale:`/`timeZone:` arguments. A compile failure is the correct red state here; do not proceed until you have seen it.

- [ ] **Step 3: Implement the minimal code to make the test pass**

In `SleepDaddy/Utilities/AccessibilityHelpers.swift`, replace the existing `formattedTimeRange` (lines 25-30) with:

```swift
    private nonisolated static let clockStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened
    )

    /// The single clock-time formatter in the app. `CombinedTimelineRail` renders its axis
    /// labels with this, and `formattedTimeRange` composes two of them.
    public static func formattedClockTime(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var style = clockStyle.locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Two clock times joined by an en dash.
    ///
    /// Deliberately not `DateIntervalFormatter`: that type ignores `dateStyle = .none` and
    /// prints both calendar dates once a range crosses midnight, which every night's sleep
    /// does.
    public static func formattedTimeRange(
        start: Date,
        end: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let from = formattedClockTime(start, locale: locale, timeZone: timeZone)
        let to = formattedClockTime(end, locale: locale, timeZone: timeZone)
        return "\(from) – \(to)"
    }
```

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareCardContentTests
```

Expected: PASS, 2 tests.

- [ ] **Step 5: Point `CombinedTimelineRail` at the shared helper**

In `SleepDaddy/Views/CombinedTimelineRail.swift`, replace lines 264-281 (the `formatted(_:)` method, the `timeStyle` static, and the `formattedTime` static) with just:

```swift
    private func formatted(_ date: Date) -> String {
        AccessibilityHelpers.formattedClockTime(date, locale: locale, timeZone: timeZone)
    }
```

- [ ] **Step 6: Update the rail's own test to call the shared helper**

`CombinedTimelineRailTests` calls `CombinedTimelineRail.formattedTime`, which Step 5 deleted. Replace the body of `timeLabelsHonorLocaleHourCycle` in `SleepDaddyTests/CombinedTimelineRailTests.swift` (lines 10-19) so the two calls read:

```swift
        let usTime = AccessibilityHelpers.formattedClockTime(
            date,
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone
        )
        let ukTime = AccessibilityHelpers.formattedClockTime(
            date,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        )
```

Leave lines 21-24 (the four `#expect`s) exactly as they are.

- [ ] **Step 7: Run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS. No `DateIntervalFormatter` references remain — confirm with `grep -rn DateIntervalFormatter SleepDaddy` returning nothing.

- [ ] **Step 8: Commit**

```bash
git add SleepDaddy/Utilities/AccessibilityHelpers.swift SleepDaddy/Views/CombinedTimelineRail.swift SleepDaddyTests/CombinedTimelineRailTests.swift SleepDaddyTests/ShareCardContentTests.swift
git commit -m "fix: stop printing calendar dates in time ranges"
```

---

## Task 2: Shorten the date header

`formattedDateHeader` uses `DateFormatter` with `dateStyle = .full`, producing `"Friday, July 31, 2026"`. The card needs `"Fri, Jul 31, 2026"` — abbreviated weekday and month, but the year always present, so an export of an older night is never ambiguous about when it happened.

**Files:**
- Modify: `SleepDaddy/Utilities/AccessibilityHelpers.swift:18-23`
- Modify: `SleepDaddyTests/ShareCardContentTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `struct ShareCardContentTests` in `SleepDaddyTests/ShareCardContentTests.swift`:

```swift
    @Test func dateHeaderAbbreviatesTheWeekdayAndMonthButKeepsTheYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let night = Self.date(year: 2026, month: 7, day: 31, hour: 22, minute: 45)

        let header = AccessibilityHelpers.formattedDateHeader(
            night, calendar: calendar, locale: Locale(identifier: "en_US")
        )

        #expect(header == "Fri, Jul 31, 2026")
    }

    @Test func dateHeaderKeepsTheYearForAnEarlierYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let night = Self.date(year: 2025, month: 7, day: 31, hour: 22, minute: 45)

        let header = AccessibilityHelpers.formattedDateHeader(
            night, calendar: calendar, locale: Locale(identifier: "en_US")
        )

        #expect(header == "Thu, Jul 31, 2025")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareCardContentTests
```

Expected: compile failure — `formattedDateHeader` takes no `calendar:` or `locale:` arguments.

- [ ] **Step 3: Implement the minimal code to make the test pass**

In `SleepDaddy/Utilities/AccessibilityHelpers.swift`, replace `formattedDateHeader` (lines 18-23) with:

```swift
    /// "Fri, Jul 31, 2026".
    ///
    /// Abbreviated rather than `.full` ("Friday, July 31, 2026"), which cost the share card
    /// most of a line. The year stays: a shared image outlives the moment it was taken, and
    /// the reader has no other cue for which year the night belongs to.
    public static func formattedDateHeader(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
            .year()
            .locale(locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
```

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareCardContentTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Utilities/AccessibilityHelpers.swift SleepDaddyTests/ShareCardContentTests.swift
git commit -m "feat: shorten the share card date header"
```

---

## Task 3: `TimelineChrome` and geometry parameterization

**Files:**
- Modify: `SleepDaddy/Layout/SleepTimelineGeometry.swift`
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:14-24`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `SleepDaddyTests/SleepTimelineGeometryTests.swift`, next to the existing
`compactTimelineGeometryKeepsEveryLaneInsideThePlotFrame` test:

```swift
    @Test func defaultChromeLeavesTheInteractiveLayoutUnchanged() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let layout = SleepTimelineCanvasVerticalLayout(totalHeight: 240)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 400,
            canvasHeight: layout.geometryHeight
        )

        #expect(layout.plotHeight == 196)
        #expect(geometry.usablePlotHeight() == 180)
        #expect(geometry.yCenterPosition(for: .awake) == 38.5)
    }

    /// On screen the stages sit 38.5pt from the top and 22.5pt from the bottom; the extra
    /// 16pt of `topPadding` clears the conflict markers. An export has no markers, so the
    /// padding shrinks and the plot reads as centred rather than as having a gutter.
    @Test func exportChromeCentersTheStagesInThePlot() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let layout = SleepTimelineCanvasVerticalLayout(totalHeight: 240, chrome: .export)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 400,
            canvasHeight: layout.geometryHeight,
            chrome: .export
        )

        let above = geometry.yCenterPosition(for: .awake)
        let below = layout.plotHeight - geometry.yCenterPosition(for: .deep)

        #expect(layout.plotHeight == 220)
        #expect(geometry.usablePlotHeight() == 216)
        #expect(above == 31)
        #expect(below == 27)
        #expect(abs(above - below) <= 5)
    }

    @Test func exportChromeHidesTheNavigatorAndCardSurface() {
        #expect(TimelineChrome.interactive.showsNavigator)
        #expect(TimelineChrome.interactive.showsCardSurface)
        #expect(TimelineChrome.interactive.axisHeight == 44)
        #expect(!TimelineChrome.export.showsNavigator)
        #expect(!TimelineChrome.export.showsCardSurface)
        #expect(TimelineChrome.export.axisHeight == 20)
    }
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

Expected: compile failure — `cannot find 'TimelineChrome' in scope`.

- [ ] **Step 3: Add `TimelineChrome`**

In `SleepDaddy/Layout/SleepTimelineGeometry.swift`, add above `public struct SleepTimelineGeometry`:

```swift
/// Selects between the on-screen timeline and the flattened variant drawn for image export.
///
/// Passed as a value rather than read from the environment because `SleepTimelineGeometry`
/// is a plain `Sendable` struct, not a `View` — the layout math is exactly what has to vary,
/// and a value keeps it constructible in tests without rendering anything.
public struct TimelineChrome: Equatable, Sendable {
    public let topPadding: CGFloat
    public let axisHeight: CGFloat
    public let showsNavigator: Bool
    public let showsCardSurface: Bool

    public init(
        topPadding: CGFloat,
        axisHeight: CGFloat,
        showsNavigator: Bool,
        showsCardSurface: Bool
    ) {
        self.topPadding = topPadding
        self.axisHeight = axisHeight
        self.showsNavigator = showsNavigator
        self.showsCardSurface = showsCardSurface
    }

    public static let interactive = TimelineChrome(
        topPadding: SleepTimelineGeometry.topPadding,
        axisHeight: SleepTimelineGeometry.timeAxisHeight,
        showsNavigator: true,
        showsCardSurface: true
    )

    /// Export drops the scrubber — there is nothing to drag in a PNG — and the card surface,
    /// because the share card draws its own and two nested cards read as a mistake. The rail
    /// shrinks to just its time-label band, and `topPadding` keeps only enough room for the
    /// top edge of the In-Bed band.
    public static let export = TimelineChrome(
        topPadding: 4,
        axisHeight: SleepTimelineGeometry.timeLabelBandHeight,
        showsNavigator: false,
        showsCardSurface: false
    )
}
```

- [ ] **Step 4: Thread the chrome through the geometry**

Four edits in `SleepDaddy/Layout/SleepTimelineGeometry.swift`.

Add the stored property after `public let canvasHeight: CGFloat` (line 9):

```swift
    public let chrome: TimelineChrome
```

Replace the initializer (lines 32-44) with:

```swift
    public init(
        totalStart: Date,
        totalEnd: Date,
        viewport: TimelineViewport,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        chrome: TimelineChrome = .interactive
    ) {
        self.totalStart = totalStart
        self.totalEnd = totalEnd
        self.viewport = viewport
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.chrome = chrome
    }

    /// Returns a copy of this geometry showing a different window of the same night.
    public func replacingViewport(_ viewport: TimelineViewport) -> Self {
        Self(
            totalStart: totalStart,
            totalEnd: totalEnd,
            viewport: viewport,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            chrome: chrome
        )
    }
```

(The existing `replacingViewport` at lines 47-55 is replaced by the version above — delete the old one so it is not duplicated.)

Replace `usablePlotHeight()` (lines 124-126) with:

```swift
    public func usablePlotHeight() -> CGFloat {
        max(1.0, canvasHeight - chrome.topPadding - chrome.axisHeight)
    }
```

In `yCenterPosition(for:displayedStages:)` (lines 132-149), replace both references to `Self.topPadding` with `chrome.topPadding`:

```swift
        guard let index = displayedStages.firstIndex(of: stage) else {
            return chrome.topPadding
        }
        let lHeight = laneHeight(displayedStagesCount: displayedStages.count)
        return chrome.topPadding + (CGFloat(index) + 0.5) * lHeight
```

Leave the statics `topPadding`, `timeAxisHeight`, `timeLabelBandHeight` and `navigatorTrackHeight` in place — `TimelineChrome.interactive` is defined in terms of them, and `SleepTimelineGeometryTests.combinedTimelineRailUsesOneCompactTouchTarget` pins their values.

- [ ] **Step 5: Give the vertical layout a chrome**

In `SleepDaddy/Views/SleepTimelineCanvas.swift`, replace the initializer of
`SleepTimelineCanvasVerticalLayout` (lines 20-23) with:

```swift
    init(totalHeight: CGFloat, chrome: TimelineChrome = .interactive) {
        plotHeight = max(1.0, totalHeight - chrome.axisHeight)
        geometryHeight = totalHeight
    }
```

- [ ] **Step 6: Run the tests and make sure they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS, including the pre-existing `timelineGeometry...` tests, which is the check that `.interactive` defaults changed nothing.

- [ ] **Step 7: Commit**

```bash
git add SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddyTests/SleepTimelineGeometryTests.swift
git commit -m "feat: add TimelineChrome to parameterize timeline layout"
```

---

## Task 4: Hide the navigator under export chrome

**Files:**
- Modify: `SleepDaddy/Views/CombinedTimelineRail.swift:23-28`, `99-146`
- Modify: `SleepDaddyTests/SnapshotTests.swift:361-381`

- [ ] **Step 1: Write the failing test**

Add to `struct SnapshotTests` in `SleepDaddyTests/SnapshotTests.swift`, directly after the
existing `combinedTimelineRailRendersAtItsSpecifiedHeight` test:

```swift
    @Test @MainActor func combinedTimelineRailUnderExportChromeDropsTheNavigator() {
        let night = makeFixtureNight()
        let rail = CombinedTimelineRail(
            night: night,
            viewport: TimelineViewport(
                normalizing: night.detectedStart,
                end: night.detectedEnd
            ),
            chrome: .export,
            onUpdateViewport: { _ in }
        )
        .frame(width: 700, height: TimelineChrome.export.axisHeight)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        renderComposition(
            of: rail,
            named: "combined timeline rail (export)",
            expecting: CGSize(width: 700, height: 20)
        )
    }
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Expected: compile failure — `CombinedTimelineRail` has no `chrome:` parameter.

- [ ] **Step 3: Give the layout a height**

In `SleepDaddy/Views/CombinedTimelineRail.swift`, replace lines 23-28 with:

```swift
struct CombinedTimelineRailLayout: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat, height: CGFloat = SleepTimelineGeometry.timeAxisHeight) {
        self.width = width
        self.height = height
    }

    private var railBounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }
```

The defaulted `height` keeps the eight `CombinedTimelineRailLayout(width: 400)` call sites in
`SleepTimelineGeometryTests` compiling unchanged.

- [ ] **Step 4: Give the rail a chrome and make the navigator conditional**

In the same file, add a stored property to `struct CombinedTimelineRail` after
`let isInteractive: Bool` (line 102):

```swift
    let chrome: TimelineChrome
```

Replace the initializer (lines 110-120) with:

```swift
    init(
        night: AssembledNight,
        viewport: TimelineViewport,
        isInteractive: Bool = true,
        chrome: TimelineChrome = .interactive,
        onUpdateViewport: @escaping (TimelineViewport) -> Void
    ) {
        self.night = night
        self.viewport = viewport
        self.isInteractive = isInteractive
        self.chrome = chrome
        self.onUpdateViewport = onUpdateViewport
    }
```

Replace the layout construction and `VStack` (lines 131-141) with:

```swift
            let layout = CombinedTimelineRailLayout(
                width: proxy.size.width,
                height: chrome.axisHeight
            )

            VStack(spacing: 0) {
                visibleTimeLabels(geometry: geometry)
                    .frame(
                        height: chrome.showsNavigator
                            ? SleepTimelineGeometry.timeLabelBandHeight
                            : chrome.axisHeight
                    )
                    .clipped()
                    .dynamicTypeSize(...DynamicTypeSize.large)

                if chrome.showsNavigator {
                    navigator(geometry: geometry, layout: layout)
                        .frame(maxHeight: .infinity)
                }
            }
```

Replace the outer frame (line 146) with:

```swift
        .frame(height: chrome.axisHeight)
```

- [ ] **Step 5: Run the tests and make sure they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Expected: PASS. The pre-existing `combinedTimelineRailRendersAtItsSpecifiedHeight` still expects 44pt, confirming the default path is untouched.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Views/CombinedTimelineRail.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: drop the timeline navigator under export chrome"
```

---

## Task 5: Flatten the canvas under export chrome

**Files:**
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:26-65`, `73`, `76-82`, `126-132`, `146`, `331-337`, `341-343`

- [ ] **Step 1: Add the chrome property and initializer parameter**

In `SleepDaddy/Views/SleepTimelineCanvas.swift`, add after `let isInteractive: Bool` (line 31):

```swift
    let chrome: TimelineChrome
```

Replace the initializer (lines 46-65) with:

```swift
    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        selectedIntervalID: String?,
        isInteractive: Bool = true,
        chrome: TimelineChrome = .interactive,
        onSelectInterval: @escaping (NormalizedSleepInterval) -> Void = { _ in },
        onUpdateViewport: @escaping (Date, Date) -> Void = { _, _ in }
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.selectedIntervalID = selectedIntervalID
        self.isInteractive = isInteractive
        self.chrome = chrome
        self.onSelectInterval = onSelectInterval
        self.onUpdateViewport = onUpdateViewport

        let initialViewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
        _interaction = State(initialValue: TimelineInteractionController(viewport: initialViewport))
    }
```

- [ ] **Step 2: Pass the chrome into layout and both geometries**

Line 73 becomes:

```swift
            let verticalLayout = SleepTimelineCanvasVerticalLayout(
                totalHeight: totalHeight,
                chrome: chrome
            )
```

The `geom` construction (lines 76-82) gains a final argument:

```swift
            let geom = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: liveViewport,
                canvasWidth: plotWidth,
                canvasHeight: verticalLayout.geometryHeight,
                chrome: chrome
            )
```

The `cGeom` construction inside the `Canvas` closure (lines 126-132) gains the same:

```swift
                            let cGeom = SleepTimelineGeometry(
                                totalStart: night.timelineStart,
                                totalEnd: night.timelineEnd,
                                viewport: liveViewport,
                                canvasWidth: canvasSize.width,
                                canvasHeight: verticalLayout.geometryHeight,
                                chrome: chrome
                            )
```

- [ ] **Step 3: Use the chrome's top padding for the In-Bed band**

Line 146 becomes:

```swift
                                let bandY = chrome.topPadding
```

- [ ] **Step 4: Pass the chrome to the rail**

Lines 331-337 become:

```swift
                    CombinedTimelineRail(
                        night: night,
                        viewport: liveViewport,
                        isInteractive: isInteractive && timelineInteractionEnabled,
                        chrome: chrome
                    ) { newViewport in
                        onUpdateViewport(newViewport.start, newViewport.end)
                    }
```

- [ ] **Step 5: Make the card surface conditional**

Add at the bottom of `SleepDaddy/Views/SleepTimelineCanvas.swift`, after the closing brace of
`SleepTimelineCanvas`:

```swift
/// The rounded, shadowed surface the timeline draws itself on when it is a card on screen.
///
/// Suppressed for export, where `ShareTimelineCardView` supplies the only surface — nesting
/// the two produces a visible card-inside-a-card.
private struct TimelineSurface: ViewModifier {
    let isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        } else {
            content
        }
    }
}
```

Then replace lines 341-343 — the `.background`, `.clipShape` and `.shadow` modifiers applied
to the `GeometryReader` — with:

```swift
        .modifier(TimelineSurface(isVisible: chrome.showsCardSurface))
```

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS. Every existing canvas call site omits `chrome:` and so still renders with the
surface, the 44pt rail, and 16pt of top padding.

- [ ] **Step 7: Commit**

```bash
git add SleepDaddy/Views/SleepTimelineCanvas.swift
git commit -m "feat: flatten the timeline canvas under export chrome"
```

---

## Task 6: The legend rule

**Files:**
- Modify: `SleepDaddy/Views/ShareTimelineCardView.swift:21-27`
- Modify: `SleepDaddyTests/ShareCardContentTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `struct ShareCardContentTests` in `SleepDaddyTests/ShareCardContentTests.swift`:

```swift
    private static func night(
        with stages: [SleepStage]
    ) -> AssembledNight {
        let base = Self.date(year: 2026, month: 7, day: 31, hour: 22, minute: 0)
        var intervals: [NormalizedSleepInterval] = []
        for (offset, stage) in stages.enumerated() {
            intervals.append(
                NormalizedSleepInterval(
                    id: "\(stage.rawValue)-\(offset)",
                    startDate: base.addingTimeInterval(Double(offset) * 3600),
                    endDate: base.addingTimeInterval(Double(offset + 1) * 3600),
                    stage: stage,
                    sourceName: "Apple Watch",
                    sourceIdentifier: "com.apple.health"
                )
            )
        }

        return AssembledNight(
            date: base,
            coreWindowStart: base,
            coreWindowEnd: base.addingTimeInterval(8 * 3600),
            detectedStart: base,
            detectedEnd: base.addingTimeInterval(8 * 3600),
            rawIntervals: intervals,
            primaryLaneIntervals: intervals.filter { $0.stage != .inBed },
            displayLaneIntervals: intervals.filter { $0.stage != .inBed },
            conflicts: [],
            summary: .empty,
            hasSleepData: true
        )
    }

    @Test func legendIsEmptyWhenTheAxisAlreadyLabelsEveryStage() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.awake, .rem, .core, .deep])
        )

        #expect(stages.isEmpty)
    }

    @Test func legendNamesUnspecifiedSleepWhenPresent() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.core, .asleepUnspecified])
        )

        #expect(stages == [.asleepUnspecified])
    }

    @Test func legendNamesInBedWhenPresent() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.core, .inBed])
        )

        #expect(stages == [.inBed])
    }

    /// Two chips is the maximum the rule can ever produce, which is what makes a second
    /// legend row structurally impossible rather than merely unlikely. The order follows
    /// `SleepStage.allCases`.
    @Test func legendNamesBothUnlabelledStagesInDeclarationOrder() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.core, .inBed, .asleepUnspecified])
        )

        #expect(stages == [.asleepUnspecified, .inBed])
    }
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareCardContentTests
```

Expected: compile failure — `type 'ShareTimelineCardView' has no member 'legendStages'`.

- [ ] **Step 3: Implement the minimal code to make the test pass**

In `SleepDaddy/Views/ShareTimelineCardView.swift`, **add** the following directly below the
existing `legendRows` static (which ends at line 27). Do not delete `legendRows` yet — `body`
still references it at line 80, and Task 7 rewrites the whole file including that reference.

```swift
    /// Stages present in the night that the timeline's left axis does not already label.
    ///
    /// The axis prints Awake/REM/Core/Deep in their theme colours beside their percentages,
    /// so a chip for any of those repeats what the reader can already see. Only
    /// `.asleepUnspecified` — drawn as a band spanning REM through Deep — and `.inBed`, a
    /// background wash, go unnamed. That caps the legend at two chips.
    ///
    /// Both collections are consulted because they hold different stages: `.inBed` lives only
    /// in `rawIntervals` (which is what `SleepTimelineCanvas` filters when drawing the
    /// background band) while `.asleepUnspecified` lives in `displayLaneIntervals`.
    static func legendStages(for night: AssembledNight) -> [SleepStage] {
        let axisLabelled = Set(SleepTimelineGeometry.defaultDisplayedStages)
        var present: Set<SleepStage> = []
        for interval in night.rawIntervals { present.insert(interval.stage) }
        for interval in night.displayLaneIntervals { present.insert(interval.stage) }

        return SleepStage.allCases.filter {
            present.contains($0) && !axisLabelled.contains($0)
        }
    }
```

- [ ] **Step 4: Regenerate the project so the new test file is in the target**

`SleepDaddyTests/ShareCardContentTests.swift` was created in Task 1. If the suite has been
running since, it is already in the target and this is a no-op; run it regardless because
`project.yml` is source-of-truth and the file is new this branch.

```bash
xcodegen generate
```

- [ ] **Step 5: Run the tests and make sure they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareCardContentTests
```

Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Views/ShareTimelineCardView.swift SleepDaddyTests/ShareCardContentTests.swift
git commit -m "feat: show legend chips only for stages the axis cannot label"
```

At this point the card still renders the old two-row legend: `legendStages` exists and is
tested but nothing calls it. Task 7 replaces the file, wiring it into `body` and removing
`legendRows`.

---

## Task 7: Rebuild the card

**Files:**
- Modify: `SleepDaddy/Views/ShareTimelineCardView.swift`
- Modify: `SleepDaddy/Utilities/SleepShareRenderer.swift:7-23`
- Modify: `SleepDaddy/Views/ContentView.swift:229-241`
- Modify: `SleepDaddyTests/ShareRendererTests.swift`

- [ ] **Step 1: Write the failing test**

Replace the whole of `SleepDaddyTests/ShareRendererTests.swift` with:

```swift
import Testing
import Foundation
import UIKit
@testable import SleepDaddy

struct ShareRendererTests {
    @MainActor
    private func renderFixtureCard(sourceFilterDescription: String?) -> UIImage? {
        let assembler = NightAssembler()
        let sampleDate = Date()
        let sampleIntervals = FixtureSleepStore.generateDefaultFixtures(
            from: sampleDate.addingTimeInterval(-86400),
            to: sampleDate.addingTimeInterval(86400)
        )

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: sampleIntervals,
            preferences: .default
        )

        return SleepShareRenderer().renderShareImage(
            night: assembled,
            viewportStart: assembled.detectedStart,
            viewportEnd: assembled.detectedEnd,
            sourceFilterDescription: sourceFilterDescription
        )
    }

    @Test @MainActor func testShareRendererGeneratesImage() {
        let image = renderFixtureCard(sourceFilterDescription: "Apple Watch")

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    /// The unfiltered case is the common one, and it must not render a "Sources:" row at all.
    @Test @MainActor func testShareRendererGeneratesImageWithoutASourceFilter() {
        let image = renderFixtureCard(sourceFilterDescription: nil)

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/ShareRendererTests
```

Expected: compile failure — `nil` is not compatible with `String`.

- [ ] **Step 3: Rebuild the card body**

Replace the whole of `SleepDaddy/Views/ShareTimelineCardView.swift` with:

```swift
import SwiftUI

public struct ShareTimelineCardView: View {
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date
    /// `nil` when the user has not filtered sources, which is the common case. The card then
    /// omits the row entirely rather than announcing "All Sources", which tells nobody
    /// anything.
    let sourceFilterDescription: String?

    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        sourceFilterDescription: String?
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.sourceFilterDescription = sourceFilterDescription
    }

    /// Stages present in the night that the timeline's left axis does not already label.
    ///
    /// The axis prints Awake/REM/Core/Deep in their theme colours beside their percentages,
    /// so a chip for any of those repeats what the reader can already see. Only
    /// `.asleepUnspecified` — drawn as a band spanning REM through Deep — and `.inBed`, a
    /// background wash, go unnamed. That caps the legend at two chips.
    ///
    /// Both collections are consulted because they hold different stages: `.inBed` lives only
    /// in `rawIntervals` (which is what `SleepTimelineCanvas` filters when drawing the
    /// background band) while `.asleepUnspecified` lives in `displayLaneIntervals`.
    static func legendStages(for night: AssembledNight) -> [SleepStage] {
        let axisLabelled = Set(SleepTimelineGeometry.defaultDisplayedStages)
        var present: Set<SleepStage> = []
        for interval in night.rawIntervals { present.insert(interval.stage) }
        for interval in night.displayLaneIntervals { present.insert(interval.stage) }

        return SleepStage.allCases.filter {
            present.contains($0) && !axisLabelled.contains($0)
        }
    }

    public var body: some View {
        let legend = Self.legendStages(for: night)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SleepDaddy")
                    .font(.caption)
                    .fontWeight(.bold)
                    // The asset resource rather than `.accentColor`: this card is drawn by
                    // ImageRenderer for export, which does not inherit the app's ambient tint.
                    .foregroundColor(.accent)

                // The headline. Percentages without a denominator are not shareable; this is
                // the one number that survives being seen for a second in a message thread.
                Text("\(AccessibilityHelpers.formattedTimeInterval(night.summary.totalSleepDuration)) asleep")
                    .font(.title)
                    .fontWeight(.bold)

                Text(
                    "\(AccessibilityHelpers.formattedDateHeader(night.date))"
                    + " · "
                    + "\(AccessibilityHelpers.formattedTimeRange(start: viewportStart, end: viewportEnd))"
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                if let sourceFilterDescription {
                    Text("Sources: \(sourceFilterDescription)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            SleepTimelineCanvas(
                night: night,
                viewportStart: viewportStart,
                viewportEnd: viewportEnd,
                selectedIntervalID: nil,
                chrome: .export,
                onSelectInterval: { _ in },
                onUpdateViewport: { _, _ in }
            )
            .frame(height: 240)
            .environment(\.timelineInteractionEnabled, false)

            if !legend.isEmpty {
                Divider()

                HStack(spacing: 14) {
                    ForEach(legend, id: \.self) { stage in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stage.themeColor)
                                .frame(width: 16, height: 16)
                            Text(stage.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 4: Widen the renderer's parameter**

In `SleepDaddy/Utilities/SleepShareRenderer.swift`, change the parameter on line 11 from
`sourceFilterDescription: String` to:

```swift
        sourceFilterDescription: String?
```

The body needs no other change — it already forwards the value straight through.

- [ ] **Step 5: Stop synthesising "All Sources"**

In `SleepDaddy/Views/ContentView.swift`, replace the `desc` binding (line 231) with:

```swift
        let desc: String? = model.preferences.selectedSourceIdentifiers.isEmpty
            ? nil
            : model.preferences.selectedSourceIdentifiers
                .compactMap { model.availableSources[$0] }
                .joined(separator: ", ")
```

- [ ] **Step 6: Run the tests and make sure they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS across every suite.

- [ ] **Step 7: Commit**

```bash
git add SleepDaddy/Views/ShareTimelineCardView.swift SleepDaddy/Utilities/SleepShareRenderer.swift SleepDaddy/Views/ContentView.swift SleepDaddyTests/ShareRendererTests.swift
git commit -m "feat: lead the share card with total sleep duration"
```

---

## Task 8: Preview the card

The card is otherwise only reachable by tapping share and dismissing a share sheet, which is a
poor loop for judging layout.

**Files:**
- Modify: `SleepDaddy/Views/ShareTimelineCardView.swift`

- [ ] **Step 1: Add previews**

Append to `SleepDaddy/Views/ShareTimelineCardView.swift`, after the closing brace of
`ShareTimelineCardView`:

```swift
#if DEBUG

private func previewNight() -> AssembledNight {
    let reference = Date(timeIntervalSinceReferenceDate: 806_000_000)
    let intervals = FixtureSleepStore.generateDefaultFixtures(
        from: reference.addingTimeInterval(-86_400),
        to: reference.addingTimeInterval(86_400)
    )
    return NightAssembler().assembleNight(
        for: reference,
        allNormalizedIntervals: intervals,
        preferences: .default
    )
}

#Preview("Share card") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.preferredViewportStart,
        viewportEnd: night.preferredViewportEnd,
        sourceFilterDescription: nil
    )
}

#Preview("Share card, source filtered") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.preferredViewportStart,
        viewportEnd: night.preferredViewportEnd,
        sourceFilterDescription: "Apple Watch"
    )
}

#Preview("Share card (dark)") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.preferredViewportStart,
        viewportEnd: night.preferredViewportEnd,
        sourceFilterDescription: nil
    )
    .preferredColorScheme(.dark)
}

// The header packs date, year and clock range into one caption run at a fixed 540pt width.
// German abbreviates none of those as tightly as English, so it is the wrap check.
#Preview("Share card (de_DE)") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.preferredViewportStart,
        viewportEnd: night.preferredViewportEnd,
        sourceFilterDescription: nil
    )
    .environment(\.locale, Locale(identifier: "de_DE"))
}

#endif
```

- [ ] **Step 2: Verify the previews build**

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Look at the card**

Open `SleepDaddy/Views/ShareTimelineCardView.swift` in Xcode and run the "Share card" preview.
Confirm by eye, against the six faults in the spec:

1. No legend row at all (the fixture night has no unspecified or in-bed intervals).
2. No minimap capsule below the time labels.
3. Roughly equal space above the Awake row and below the Deep row.
4. No "Sources:" line.
5. The header line reads `Fri, Jul 31, 2026 · 10:45 PM – 7:17 AM` on one line — not
   `Friday, July 31, 2026` and not `7/31/2026, 10:45 PM – 8/1/2026, 7:17 AM`.
6. The duration is the largest text on the card.
7. No inner rounded rectangle or shadow around the plot — one card, not two.

Then run the "Share card (de_DE)" preview and confirm the header line still fits on one line.
If it wraps, drop `· ` in favour of putting the clock range on its own `caption2` line — the
card has the vertical budget for it now.

- [ ] **Step 4: Run the full suite one last time**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Views/ShareTimelineCardView.swift
git commit -m "test: preview the share card without the share sheet"
```

---

## Verification against the original review

| Fault | Fixed by |
|---|---|
| Legend takes two rows | Task 6 + Task 7 (`legendStages`, conditional legend block) |
| Minimap is inert | Task 4 (`chrome.showsNavigator`) |
| Gutter above Awake | Task 3 (`chrome.topPadding` 16 → 4) |
| "Sources: All Sources" | Task 7 (`String?`, `nil` when unfiltered) |
| Verbose date range | Task 1 (`formattedTimeRange`) + Task 2 (`formattedDateHeader`) |
| "Visible Range" headline | Task 7 (`totalSleepDuration` hero) |
| Card inside a card | Task 5 (`chrome.showsCardSurface`) |
