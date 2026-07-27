# Live Timeline Navigator Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the bottom navigator synchronized with the chart throughout pinch and drag gestures while committing durable viewport state only when interaction settles.

**Architecture:** Add a small value type that selects a transient chart viewport over the model's committed viewport. `SelectedNightDetailView` owns that state, passes its selected viewport to `SlimContextNavigator`, and receives live and settled callbacks from `SleepTimelineCanvas`; the interaction controller and model retain their existing responsibilities. Increase fixed screen-point stroke widths in the canvas while preserving the hierarchy between stages, transitions, and selection emphasis.

**Tech Stack:** Swift 6, SwiftUI, UIKit gesture recognizers, Swift Testing, iOS 26+

## Global Constraints

- HealthKit remains read-only.
- Do not add or commit generated `SleepDaddy.xcodeproj` or `Info.plist` files.
- Keep timeline geometry and interaction logic independently testable outside rendered SwiftUI pixels.
- Both chart pinch and chart drag gestures update navigator feedback live.
- `NightBrowserModel` receives only the settled viewport at gesture completion.
- Horizontal stage strokes are 10 points, transition connectors are 6 points, and selected-stage emphasis uses a 14-point white outline with a 10-point colored center.
- The chart always uses Awake, REM, Core, and Deep rows; `.asleepUnspecified` uses its existing theme color in a rounded band spanning REM through Deep.
- Major time labels clamp their measured bounds inside the plot while interior labels remain centered on their ticks.
- Loaded content fills the available navigation area and remains top-aligned for both populated and empty nights.

---

### Task 1: Transient Viewport Presentation State

**Files:**
- Create: `SleepDaddy/Layout/TimelineViewportPresentation.swift`
- Create: `SleepDaddyTests/TimelineViewportPresentationTests.swift`

**Interfaces:**
- Consumes: `TimelineViewport`
- Produces: `TimelineViewportPresentation.liveViewport`, `displayedViewport(committed:)`, `updateLiveViewport(_:)`, and `clearLiveViewport()`

- [ ] **Step 1: Write the failing state-selection tests**

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct TimelineViewportPresentationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func liveViewportOverridesCommittedViewport() {
        let committed = TimelineViewport(
            start: start,
            end: start.addingTimeInterval(12 * 3600)
        )
        let live = TimelineViewport(
            start: start.addingTimeInterval(3 * 3600),
            end: start.addingTimeInterval(7 * 3600)
        )
        var presentation = TimelineViewportPresentation()

        presentation.updateLiveViewport(live)

        #expect(presentation.displayedViewport(committed: committed) == live)
    }

    @Test func clearingLiveViewportFallsBackToLatestCommittedViewport() {
        let original = TimelineViewport(
            start: start,
            end: start.addingTimeInterval(12 * 3600)
        )
        let live = TimelineViewport(
            start: start.addingTimeInterval(3 * 3600),
            end: start.addingTimeInterval(7 * 3600)
        )
        let newlyCommitted = TimelineViewport(
            start: start.addingTimeInterval(2 * 3600),
            end: start.addingTimeInterval(8 * 3600)
        )
        var presentation = TimelineViewportPresentation()
        presentation.updateLiveViewport(live)

        presentation.clearLiveViewport()

        #expect(presentation.displayedViewport(committed: newlyCommitted) == newlyCommitted)
        #expect(presentation.displayedViewport(committed: original) == original)
    }
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineViewportPresentationTests
```

Expected: FAIL because `TimelineViewportPresentation` does not exist.

- [ ] **Step 3: Implement the minimal presentation state**

```swift
import Foundation

public struct TimelineViewportPresentation: Sendable {
    public private(set) var liveViewport: TimelineViewport?

    public init(liveViewport: TimelineViewport? = nil) {
        self.liveViewport = liveViewport
    }

    public func displayedViewport(committed: TimelineViewport) -> TimelineViewport {
        liveViewport ?? committed
    }

    public mutating func updateLiveViewport(_ viewport: TimelineViewport) {
        liveViewport = viewport
    }

    public mutating func clearLiveViewport() {
        liveViewport = nil
    }
}
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run the command from Step 2.

Expected: PASS with both presentation tests successful.

- [ ] **Step 5: Commit the tested state type**

```bash
git add SleepDaddy/Layout/TimelineViewportPresentation.swift SleepDaddyTests/TimelineViewportPresentationTests.swift
git commit -m "feat: model live timeline viewport presentation"
```

### Task 2: Publish Live Chart Viewports

**Files:**
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:14-51, 215-250`
- Modify: `SleepDaddyTests/SnapshotTests.swift` at every `SleepTimelineCanvas` initializer if compilation requires explicit callback arguments

**Interfaces:**
- Consumes: `TimelineInteractionController.liveViewport`
- Produces: `SleepTimelineCanvas.onUpdateLiveViewport: (TimelineViewport?) -> Void`

- [ ] **Step 1: Add the callback contract before wiring gesture changes**

Add an optional callback to `SleepTimelineCanvas`:

```swift
let onUpdateLiveViewport: (TimelineViewport?) -> Void
```

Add the initializer argument with a default:

```swift
onUpdateLiveViewport: @escaping (TimelineViewport?) -> Void = { _ in }
```

Assign it in the initializer. Do not call it yet.

- [ ] **Step 2: Run the focused presentation tests and build**

Run:

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS; the default closure preserves existing call sites.

- [ ] **Step 3: Publish each live pan and pinch update**

After each controller mutation, report its viewport:

```swift
interaction.updatePan(translationX: translationX, geometry: geom)
onUpdateLiveViewport(interaction.liveViewport)
```

```swift
interaction.updateMagnification(scale, anchorX: centroidX, geometry: geom)
onUpdateLiveViewport(interaction.liveViewport)
```

At gesture begin, report the reset controller viewport:

```swift
interaction.begin(viewport: TimelineViewport(normalizing: viewportStart, end: viewportEnd))
onUpdateLiveViewport(interaction.liveViewport)
```

- [ ] **Step 4: Clear transient feedback after settling or cancellation**

In `onInteractionEnded`, call the existing `onUpdateViewport` first and then:

```swift
onUpdateLiveViewport(nil)
```

In each external-change `.onChange` handler, clear the live callback after cancelling:

```swift
interaction.cancel(viewport: vp)
onUpdateLiveViewport(nil)
```

- [ ] **Step 5: Build to verify callback wiring compiles**

Run the build command from Step 2.

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit chart publication**

```bash
git add SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: publish live chart viewport updates"
```

### Task 3: Drive the Navigator from Live Feedback

**Files:**
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift:3-39`
- Test: `SleepDaddyTests/TimelineViewportPresentationTests.swift`

**Interfaces:**
- Consumes: `TimelineViewportPresentation`, `SleepTimelineCanvas.onUpdateLiveViewport`
- Produces: live `viewportStart` and `viewportEnd` arguments for `SlimContextNavigator`

- [ ] **Step 1: Add presentation state and derive committed/displayed viewports**

Add:

```swift
@State private var viewportPresentation = TimelineViewportPresentation()
```

Inside the selected-night branch, derive:

```swift
let committedViewport = TimelineViewport(
    normalizing: model.viewportStart,
    end: model.viewportEnd
)
let displayedViewport = viewportPresentation.displayedViewport(
    committed: committedViewport
)
```

- [ ] **Step 2: Connect chart live updates**

Pass:

```swift
onUpdateLiveViewport: { liveViewport in
    if let liveViewport {
        viewportPresentation.updateLiveViewport(liveViewport)
    } else {
        viewportPresentation.clearLiveViewport()
    }
}
```

Keep the existing settled `onUpdateViewport` callback unchanged.

- [ ] **Step 3: Render the navigator from the displayed viewport**

Replace the navigator arguments with:

```swift
viewportStart: displayedViewport.start,
viewportEnd: displayedViewport.end
```

Keep navigator-originated updates writing directly to the model.

- [ ] **Step 4: Run focused tests and the complete test suite**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineViewportPresentationTests
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: both commands finish with `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the standard build**

Run:

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Review the final diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the intended implementation files and pre-existing `.agents/` entry are present.

- [ ] **Step 7: Commit the integration**

```bash
git add SleepDaddy/Views/SelectedNightDetailView.swift
git commit -m "fix: synchronize timeline navigator during gestures"
```

### Task 4: Increase Timeline Stage Stroke Weight

**Files:**
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:145-184`
- Verify: `SleepDaddyTests/SnapshotTests.swift`
- Verify/update: snapshot reference images used by `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: existing `TimelineStepSegment.isConnector` and selected-stage rendering
- Produces: 10-point stage strokes, 6-point connectors, and 14/10-point selected emphasis

- [ ] **Step 1: Change the canvas stroke widths**

Use 6 points for connector segments:

```swift
style: StrokeStyle(lineWidth: 6, lineCap: .round)
```

Use 10 points for horizontal stage segments:

```swift
style: StrokeStyle(lineWidth: 10, lineCap: .round)
```

Use a 14-point white selected-stage outline and redraw the colored center at 10 points:

```swift
style: StrokeStyle(lineWidth: 14, lineCap: .round)
```

```swift
style: StrokeStyle(lineWidth: 10, lineCap: .round)
```

- [ ] **Step 2: Run the focused canvas snapshot tests**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Expected: snapshot comparisons that cover `SleepTimelineCanvas` fail only where the
intentional stroke-width change alters rendered pixels.

- [ ] **Step 3: Inspect generated snapshot failures**

Open the generated failure images and confirm:

- Horizontal stage segments are visibly heavier without touching neighboring stage rows.
- Transition connectors remain narrower than horizontal stage segments.
- The selected interval retains a visible white outline around its colored center.
- Labels, tick marks, navigator layout, and card bounds are unchanged.

- [ ] **Step 4: Update only affected snapshot references**

Replace only the reference PNGs whose differences are caused by the approved 10/6/14-point
stroke treatment. Do not accept unrelated pixel differences.

- [ ] **Step 5: Re-run snapshot tests and the full suite**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: both commands finish with `** TEST SUCCEEDED **`.

- [ ] **Step 6: Run the standard build and inspect the diff**

Run:

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
git diff --check
git status --short
```

Expected: `** BUILD SUCCEEDED **`, no whitespace errors, and only approved source, test,
snapshot, and documentation changes plus the pre-existing `.agents/` entry.

- [ ] **Step 7: Commit the visual change**

```bash
git add SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddyTests
git commit -m "style: increase timeline stage weight"
```

### Task 5: Render Unspecified Sleep Across Specific Sleep Rows

**Files:**
- Modify: `SleepDaddy/Layout/SleepTimelineGeometry.swift:54-113, 242-286`
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:68-184`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`
- Verify: `SleepDaddyTests/SnapshotTests.swift`
- Verify/update: affected snapshot reference PNGs

**Interfaces:**
- Consumes: `SleepStage.asleepUnspecified`, the fixed four-stage display list
- Produces: `SleepTimelineGeometry.rect(for:displayedStages:)` spanning REM through Deep for unspecified sleep; centered connector geometry; selectable spanning bands

- [ ] **Step 1: Write failing geometry tests for the spanning band**

Add a fixture containing an `.asleepUnspecified` interval and assert independently derived
four-row geometry:

```swift
@Test func unspecifiedSleepRectSpansRemThroughDeepRows() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let end = start.addingTimeInterval(12 * 3600)
    let geometry = SleepTimelineGeometry(
        totalStart: start,
        totalEnd: end,
        viewport: TimelineViewport(start: start, end: end),
        canvasWidth: 400,
        canvasHeight: 300
    )
    let interval = NormalizedSleepInterval(
        id: "unspecified",
        startDate: start.addingTimeInterval(3 * 3600),
        endDate: start.addingTimeInterval(6 * 3600),
        stage: .asleepUnspecified,
        sourceName: "Fixture",
        sourceIdentifier: "fixture"
    )

    let rect = geometry.rect(for: interval)

    #expect(abs(rect.minX - 100) < 0.001)
    #expect(abs(rect.maxX - 200) < 0.001)
    #expect(abs(rect.minY - 94) < 0.001)
    #expect(abs(rect.maxY - 258) < 0.001)
}
```

The expected Y values are hand-derived from a 300-point canvas: usable height 256, four
64-point lanes, and a 36-point capped row height.

- [ ] **Step 2: Write failing connector and hit-testing tests**

Add:

```swift
@Test func unspecifiedSleepUsesCenterOfSleepRowsForConnectors() {
    // Arrange contiguous Core -> Asleep Unspecified -> REM intervals.
    // Assert both connectors meet the unspecified interval at y = 176,
    // the midpoint between the REM and Deep row centers.
}

@Test func unspecifiedSleepCanBeHitAnywhereInsideSpanningBand() {
    // Use the same four-row geometry and unspecified fixture.
    // Assert a point inside the Deep portion of its rectangle returns the interval.
}
```

Use literal dates, points, and expected Y coordinates. The production mutations these tests
catch are falling back to top padding for an absent fifth row and retaining a one-row hit
target.

- [ ] **Step 3: Run focused geometry tests to verify they fail**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

Expected: FAIL because unspecified sleep still resolves as a fifth/missing row rather than
the REM-through-Deep band.

- [ ] **Step 4: Implement unspecified geometry**

Keep `defaultDisplayedStages` fixed at `[.awake, .rem, .core, .deep]`.

In `yCenterPosition`, when the requested stage is `.asleepUnspecified` and the displayed
stages contain REM and Deep, return the midpoint of those two row centers.

In `rect(for:displayedStages:)`, special-case `.asleepUnspecified`: use the REM row's top
edge as `minY` and the Deep row's bottom edge as `maxY`. Preserve the normal X calculation
and minimum width.

The existing `intervalAt` then gains the spanning hit target through `rect`, while
`stepSegments` gains centered connectors through `yCenterPosition`.

- [ ] **Step 5: Run focused geometry tests to verify they pass**

Run the command from Step 3.

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Render unspecified intervals as spanning rounded bands**

In `SleepTimelineCanvas`:

- Remove the conditional fifth `.asleepUnspecified` display row and always use
  `SleepTimelineGeometry.defaultDisplayedStages`.
- Before drawing step segments, draw every `.asleepUnspecified` primary interval using
  `cGeom.rect(for:displayedStages:)`, its existing theme color, and a rounded rectangle.
- Do not draw the unspecified interval's horizontal `TimelineStepSegment`; retain connector
  segments into and out of it.
- When an unspecified interval is selected, stroke its full rounded rectangle in white.
  Keep the existing selected-line treatment for specific stages.

- [ ] **Step 7: Run and inspect snapshot failures**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Inspect each generated failure image. Confirm that:

- Only four labeled rows remain.
- Unspecified sleep spans REM through Deep in the existing muted-violet color.
- Specific stages and connectors remain readable.
- No band overlaps Awake or the time axis.
- The selected band, if present in a fixture, has a visible white outline.

- [ ] **Step 8: Update only affected snapshot references and verify**

Replace only references changed by the approved rendering. Then run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: snapshot tests and the full suite report `** TEST SUCCEEDED **`; the build reports
`** BUILD SUCCEEDED **`.

- [ ] **Step 9: Review and commit**

Run:

```bash
git diff --check
git status --short
```

Then commit only the approved implementation and updated references:

```bash
git add SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddyTests
git commit -m "feat: span unspecified sleep across stage rows"
```

### Task 6: Keep Edge Time Labels Inside the Plot

**Files:**
- Modify: `SleepDaddy/Layout/SleepTimelineGeometry.swift`
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:187-207`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`
- Verify/update: affected snapshot reference PNGs

**Interfaces:**
- Consumes: tick X position, measured label width, `canvasWidth`
- Produces: `SleepTimelineGeometry.clampedLabelCenterX(tickX:labelWidth:) -> CGFloat`

- [ ] **Step 1: Write failing label-position tests**

Add:

```swift
@Test func timeLabelCenterIsClampedInsideCanvasEdges() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let geometry = SleepTimelineGeometry(
        totalStart: start,
        totalEnd: start.addingTimeInterval(3600),
        viewport: TimelineViewport(
            start: start,
            end: start.addingTimeInterval(3600)
        ),
        canvasWidth: 400,
        canvasHeight: 300
    )

    #expect(geometry.clampedLabelCenterX(tickX: 0, labelWidth: 80) == 40)
    #expect(geometry.clampedLabelCenterX(tickX: 200, labelWidth: 80) == 200)
    #expect(geometry.clampedLabelCenterX(tickX: 400, labelWidth: 80) == 360)
}

@Test func timeLabelWiderThanCanvasCentersInCanvas() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let geometry = SleepTimelineGeometry(
        totalStart: start,
        totalEnd: start.addingTimeInterval(3600),
        viewport: TimelineViewport(
            start: start,
            end: start.addingTimeInterval(3600)
        ),
        canvasWidth: 60,
        canvasHeight: 300
    )

    #expect(geometry.clampedLabelCenterX(tickX: 0, labelWidth: 80) == 30)
}
```

These tests catch a missing leading/trailing clamp and an inverted clamp range when a label
is wider than its canvas.

- [ ] **Step 2: Run focused geometry tests to verify they fail**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

Expected: FAIL because `clampedLabelCenterX(tickX:labelWidth:)` does not exist.

- [ ] **Step 3: Implement the pure clamping helper**

Add:

```swift
public func clampedLabelCenterX(tickX: CGFloat, labelWidth: CGFloat) -> CGFloat {
    let width = max(0, labelWidth)
    guard width <= canvasWidth else {
        return canvasWidth / 2
    }
    let halfWidth = width / 2
    return min(canvasWidth - halfWidth, max(halfWidth, tickX))
}
```

- [ ] **Step 4: Run focused geometry tests to verify they pass**

Run the command from Step 2.

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Measure and clamp resolved tick labels**

In the major-tick branch of `SleepTimelineCanvas`, resolve and measure the `Text` before
drawing:

```swift
let resolvedText = context.resolve(text)
let measuredSize = resolvedText.measure(
    in: CGSize(width: canvasSize.width, height: .infinity)
)
let labelX = cGeom.clampedLabelCenterX(
    tickX: tick.x,
    labelWidth: measuredSize.width
)
context.draw(
    resolvedText,
    at: CGPoint(x: labelX, y: labelY),
    anchor: .center
)
```

- [ ] **Step 6: Run snapshots and inspect the affected image**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Confirm that the leading time is fully visible, interior labels remain centered on their
ticks, and the trailing label stays inside the plot. Update only references changed by the
approved label positioning and earlier approved visual changes.

- [ ] **Step 7: Run full verification**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
git diff --check
git status --short
```

Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`, no whitespace errors, and only
approved implementation/snapshot changes plus the pre-existing `.agents/` entry.

- [ ] **Step 8: Commit**

```bash
git add SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddyTests
git commit -m "fix: keep timeline labels inside plot"
```

### Task 7: Top-Align Empty Loaded Nights

**Files:**
- Modify: `SleepDaddy/Views/ContentView.swift:88-115`
- Modify: `SleepDaddyTests/SnapshotTests.swift`
- Create/update: the empty-loaded-night snapshot reference PNG

**Interfaces:**
- Consumes: `NightBrowserModel.appState == .loaded` and existing empty-night detail
- Produces: a full-height, top-aligned loaded-state container

- [ ] **Step 1: Add a failing phone-sized empty-night snapshot**

Create a deterministic `NightBrowserModel` fixture whose app state is loaded and whose
selected assembled night has no eligible sleep records. Render `ContentView(model:)` at the
same portrait phone dimensions used by the existing composite snapshots in dark mode.

The snapshot must include the navigation bar, `NightHeaderView`, divider, and empty-state
card so it fails against the current vertically centered layout.

- [ ] **Step 2: Run the focused snapshot test to verify it fails**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/testSnapshotEmptyLoadedNight
```

Expected: FAIL because the current loaded-state group is centered vertically and does not
match the approved top-aligned reference.

- [ ] **Step 3: Apply the minimal parent-layout fix**

On the `.loaded` case’s inner `VStack`, add:

```swift
.frame(
    maxWidth: .infinity,
    maxHeight: .infinity,
    alignment: .top
)
```

Do not add an empty-state spacer, offset, fixed screen height, or new `ScrollView`.

- [ ] **Step 4: Render and inspect the new snapshot**

Generate the candidate image and confirm:

- The night header begins directly below the navigation bar.
- The divider and empty card follow with their existing padding.
- No large flexible gap appears above the header.
- The empty card retains its existing size, text, and styling.

Accept the new reference only after this visual inspection.

- [ ] **Step 5: Run focused and full verification**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
git diff --check
git status --short
```

Expected: all snapshot tests and the full suite report `** TEST SUCCEEDED **`; the build
reports `** BUILD SUCCEEDED **`; no whitespace errors; only the intended source, snapshot,
and documentation changes plus pre-existing `.agents/`.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Views/ContentView.swift SleepDaddyTests
git commit -m "fix: top-align empty loaded nights"
```
