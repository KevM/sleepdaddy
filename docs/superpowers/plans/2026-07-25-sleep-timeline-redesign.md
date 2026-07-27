# Sleep Timeline Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-height, Apple Health-inspired stepped sleep timeline with live Maps-style pan and pinch, compact night navigation, minimal controls, and correct newest-night startup.

**Architecture:** A pure `TimelineViewport` and `TimelineInteractionController` calculate every live viewport independently of SwiftUI. `SleepTimelineGeometry` converts that viewport into stepped-path, tick, hit-test, and navigator geometry. SwiftUI views render the live viewport, while `NightBrowserModel` owns only the selected night and settled viewport.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, `MagnifyGesture`, `DragGesture`, Observation, Swift Testing, iOS 26+, XcodeGen.

## Global Constraints

- HealthKit access remains read-only.
- Do not commit generated `SleepDaddy.xcodeproj` or `Info.plist` files.
- Modify `project.yml` only if target configuration changes; this plan requires no project configuration change.
- Geometry and interaction calculations must remain testable without rendered UI pixels.
- The minimum viewport duration is exactly five minutes.
- The maximum viewport is the selected night’s complete detected range.
- Icon-only controls require explicit accessibility labels and at least 44-by-44-point hit targets.
- Reduce Motion disables inertial continuation and minimizes directional transitions.
- Preserve unrelated user changes already present in the worktree.

---

## File Map

**Create**

- `SleepDaddy/Layout/TimelineViewport.swift` — validated visible date range.
- `SleepDaddy/Layout/TimelineInteractionController.swift` — live pan, focal zoom, resistance, and settling math.
- `SleepDaddy/Views/NightHeaderView.swift` — compact adjacent-night navigation and calendar presentation.
- `SleepDaddy/Views/CompactSourceFilterButton.swift` — icon-only filter entry point and source sheet.
- `SleepDaddy/Views/TimelineGestureOverlay.swift` — narrowly scoped UIKit touch measurement for live pinch centroid and simultaneous pan.
- `SleepDaddyTests/TimelineInteractionControllerTests.swift` — deterministic direct-manipulation tests.

**Modify**

- `SleepDaddy/Layout/SleepTimelineGeometry.swift` — viewport-based conversion, stepped path, ticks, and navigator math.
- `SleepDaddy/Views/SleepTimelineCanvas.swift` — full live rendering and gesture pipeline.
- `SleepDaddy/Views/SlimContextNavigator.swift` — continuous window drag and recenter.
- `SleepDaddy/Views/SelectedNightDetailView.swift` — flexible-height layout and removal of old controls.
- `SleepDaddy/Views/ContentView.swift` — remove persistent night strip and decorative branding; install compact actions.
- `SleepDaddy/ViewModels/NightBrowserModel.swift` — newest populated startup and bounded adjacent navigation.
- `SleepDaddyTests/SleepTimelineGeometryTests.swift` — viewport, step-path, tick, and hit-test coverage.
- `SleepDaddyTests/NightBrowserModelTests.swift` — startup and adjacent navigation coverage.
- `SleepDaddyTests/SnapshotTests.swift` — new visual snapshot composition.

**Delete**

- `SleepDaddy/Views/SourceFilterView.swift` after its source-list behavior is moved into `CompactSourceFilterButton`.
- `SleepDaddy/Views/MultiNightOverviewStrip.swift` after `NightHeaderView` replaces it.

---

### Task 1: Introduce the viewport value and focal zoom geometry

**Files:**
- Create: `SleepDaddy/Layout/TimelineViewport.swift`
- Modify: `SleepDaddy/Layout/SleepTimelineGeometry.swift`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`

**Interfaces:**
- Produces: `TimelineViewport(start:end:)`, `duration`, and `SleepTimelineGeometry.clamped(_:)`.
- Produces: `SleepTimelineGeometry.zoomed(_:magnification:anchorX:) -> TimelineViewport`.
- Consumes: selected-night total start/end dates and canvas size.

- [ ] **Step 1: Write failing viewport and focal-anchor tests**

Add tests that use fixed reference dates rather than `Date()`:

```swift
@Test func focalZoomPreservesDateBelowAnchor() {
    let totalStart = Date(timeIntervalSinceReferenceDate: 0)
    let totalEnd = totalStart.addingTimeInterval(12 * 3600)
    let viewport = TimelineViewport(start: totalStart, end: totalEnd)
    let geometry = SleepTimelineGeometry(
        totalStart: totalStart,
        totalEnd: totalEnd,
        viewport: viewport,
        canvasWidth: 400,
        canvasHeight: 300
    )

    let anchorX: CGFloat = 100
    let anchorDate = geometry.date(atX: anchorX)
    let zoomed = geometry.zoomed(viewport, magnification: 2, anchorX: anchorX)
    let zoomedGeometry = geometry.replacingViewport(zoomed)

    #expect(abs(zoomed.duration - 6 * 3600) < 0.001)
    #expect(abs(zoomedGeometry.date(atX: anchorX).timeIntervalSince(anchorDate)) < 0.001)
}

@Test func viewportClampsToFiveMinutesAndFullNight() {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let end = start.addingTimeInterval(12 * 3600)
    let geometry = SleepTimelineGeometry(
        totalStart: start,
        totalEnd: end,
        viewport: TimelineViewport(start: start, end: end),
        canvasWidth: 400,
        canvasHeight: 300
    )

    let tooSmall = TimelineViewport(start: start.addingTimeInterval(3600),
                                    end: start.addingTimeInterval(3660))
    let clampedSmall = geometry.clamped(tooSmall, anchorDate: tooSmall.midpoint)
    #expect(abs(clampedSmall.duration - 300) < 0.001)

    let tooLarge = TimelineViewport(start: start.addingTimeInterval(-3600),
                                    end: end.addingTimeInterval(3600))
    #expect(geometry.clamped(tooLarge) == TimelineViewport(start: start, end: end))
}
```

- [ ] **Step 2: Run the geometry tests and confirm the new API is missing**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

Expected: FAIL because `TimelineViewport`, the viewport initializer, `replacingViewport`, and viewport-based zoom/clamp methods do not exist.

- [ ] **Step 3: Implement the minimal viewport and geometry API**

Create:

```swift
import Foundation

public struct TimelineViewport: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        precondition(end > start, "TimelineViewport end must follow start")
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var midpoint: Date { start.addingTimeInterval(duration / 2) }

    public func shifted(by interval: TimeInterval) -> Self {
        Self(start: start.addingTimeInterval(interval),
             end: end.addingTimeInterval(interval))
    }
}
```

Refactor `SleepTimelineGeometry` to store `viewport: TimelineViewport`, expose `minimumViewportDuration = 300`, and add:

```swift
public func replacingViewport(_ viewport: TimelineViewport) -> Self
public func clamped(_ proposed: TimelineViewport, anchorDate: Date? = nil) -> TimelineViewport
public func zoomed(
    _ baseline: TimelineViewport,
    magnification: CGFloat,
    anchorX: CGFloat
) -> TimelineViewport
public func panned(_ baseline: TimelineViewport, deltaX: CGFloat) -> TimelineViewport
```

Use `anchorRatio = anchorX / canvasWidth`; calculate the baseline anchor date from the baseline viewport, then position the new viewport so that date remains at the same ratio. Clamp duration to `300...totalDuration`.

- [ ] **Step 4: Run geometry tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit the viewport foundation**

```bash
git add SleepDaddy/Layout/TimelineViewport.swift SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddyTests/SleepTimelineGeometryTests.swift
git commit -m "refactor: model timeline viewport explicitly"
```

---

### Task 2: Build and test the live interaction controller

**Files:**
- Create: `SleepDaddy/Layout/TimelineInteractionController.swift`
- Create: `SleepDaddyTests/TimelineInteractionControllerTests.swift`

**Interfaces:**
- Consumes: `TimelineViewport` and `SleepTimelineGeometry`.
- Produces: `begin(viewport:)`, `updatePan(translationX:geometry:)`, `updateMagnification(_:anchorX:geometry:)`, `liveViewport`, `settledViewport(geometry:velocityX:reduceMotion:)`.
- Produces: `cancel(viewport:)` for night changes.

- [ ] **Step 1: Write failing stable-baseline and combined-transform tests**

```swift
@Test func repeatedMagnificationUsesGestureBaseline() {
    let fixture = InteractionFixture()
    var controller = TimelineInteractionController(viewport: fixture.fullViewport)
    controller.begin(viewport: fixture.fullViewport)

    controller.updateMagnification(1.5, anchorX: 200, geometry: fixture.geometry)
    controller.updateMagnification(2.0, anchorX: 200, geometry: fixture.geometry)

    #expect(abs(controller.liveViewport.duration - 6 * 3600) < 0.001)
}

@Test func simultaneousPanAndZoomCombineFromOneBaseline() {
    let fixture = InteractionFixture()
    var controller = TimelineInteractionController(viewport: fixture.fullViewport)
    controller.begin(viewport: fixture.fullViewport)
    controller.updatePan(translationX: -40, geometry: fixture.geometry)
    controller.updateMagnification(2, anchorX: 200, geometry: fixture.geometry)

    let expectedZoom = fixture.geometry.zoomed(fixture.fullViewport,
                                                magnification: 2,
                                                anchorX: 200)
    let expected = fixture.geometry.panned(expectedZoom, deltaX: -40)
    #expect(controller.liveViewport == expected)
}
```

Add tests for edge resistance, settled clamping, velocity direction, and Reduce Motion:

```swift
@Test func reduceMotionSettlesWithoutInertia() {
    let fixture = InteractionFixture()
    var controller = TimelineInteractionController(viewport: fixture.middleViewport)
    controller.begin(viewport: fixture.middleViewport)
    let settled = controller.settledViewport(
        geometry: fixture.geometry,
        velocityX: -2_000,
        reduceMotion: true
    )
    #expect(settled == fixture.middleViewport)
}
```

- [ ] **Step 2: Run the controller tests and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineInteractionControllerTests
```

Expected: FAIL because `TimelineInteractionController` is missing.

- [ ] **Step 3: Implement controller state and pure interaction math**

Implement as a value type so `@State` can own it:

```swift
public struct TimelineInteractionController: Sendable {
    public private(set) var liveViewport: TimelineViewport
    private var baselineViewport: TimelineViewport
    private var panTranslationX: CGFloat = 0
    private var magnification: CGFloat = 1
    private var anchorX: CGFloat = 0

    public init(viewport: TimelineViewport) { /* initialize both viewports */ }
    public mutating func begin(viewport: TimelineViewport) { /* reset session */ }
    public mutating func updatePan(
        translationX: CGFloat,
        geometry: SleepTimelineGeometry
    )
    public mutating func updateMagnification(
        _ magnification: CGFloat,
        anchorX: CGFloat,
        geometry: SleepTimelineGeometry
    )
    public mutating func settledViewport(
        geometry: SleepTimelineGeometry,
        velocityX: CGFloat,
        reduceMotion: Bool
    ) -> TimelineViewport
    public mutating func cancel(viewport: TimelineViewport)
}
```

Recompute each live viewport from `baselineViewport` plus the latest pan and magnification values. Do not feed `liveViewport` back as the next baseline. Apply a resistance curve only to temporary overscroll; `settledViewport` must return `geometry.clamped(...)`. Use a capped projected translation derived from velocity when Reduce Motion is false.

- [ ] **Step 4: Run controller and geometry tests**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineInteractionControllerTests -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

Expected: PASS.

- [ ] **Step 5: Commit the interaction controller**

```bash
git add SleepDaddy/Layout/TimelineInteractionController.swift SleepDaddyTests/TimelineInteractionControllerTests.swift
git commit -m "feat: add live timeline interaction controller"
```

---

### Task 3: Add stepped-path, tick, and live hit-test geometry

**Files:**
- Modify: `SleepDaddy/Layout/SleepTimelineGeometry.swift`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`

**Interfaces:**
- Consumes: ordered `[NormalizedSleepInterval]` and a live `TimelineViewport`.
- Produces: `stepSegments(for:) -> [TimelineStepSegment]`.
- Produces: `timeTicks(calendar:) -> [TimelineTimeTick]`.
- Produces: existing interval hit-testing against the live viewport.

- [ ] **Step 1: Write failing step and tick tests**

Define expected semantics explicitly:

```swift
@Test func consecutiveStagesProduceHorizontalSegmentsAndConnector() {
    let first = interval(id: "core", start: 0, end: 1_800, stage: .core)
    let second = interval(id: "deep", start: 1_800, end: 3_600, stage: .deep)
    let segments = geometry.stepSegments(for: [first, second])

    #expect(segments.filter(\.isConnector).count == 1)
    #expect(segments.count == 3)
    #expect(segments[0].end.x == segments[1].start.x)
    #expect(segments[1].end.y == segments[2].start.y)
}

@Test func twelveHourViewportUsesSparseTicks() {
    let ticks = geometry.timeTicks(calendar: calendar)
    #expect(ticks.count >= 4)
    #expect(ticks.count <= 7)
    #expect(ticks.allSatisfy { calendar.component(.minute, from: $0.date) == 0 })
}

@Test func thirtyMinuteViewportUsesFiveMinuteTicks() {
    let zoomed = geometry.replacingViewport(
        TimelineViewport(start: start, end: start.addingTimeInterval(1_800))
    )
    let ticks = zoomed.timeTicks(calendar: calendar)
    let deltas = zip(ticks, ticks.dropFirst()).map {
        $1.date.timeIntervalSince($0.date)
    }
    #expect(deltas.allSatisfy { abs($0 - 300) < 0.001 })
}
```

- [ ] **Step 2: Run geometry tests and verify the missing geometry fails**

Run the Task 1 geometry-test command.

Expected: FAIL because `TimelineStepSegment`, `TimelineTimeTick`, `stepSegments`, and `timeTicks` are missing.

- [ ] **Step 3: Implement render primitives**

Add:

```swift
public struct TimelineStepSegment: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint
    public let stage: SleepStage
    public let isConnector: Bool
}

public struct TimelineTimeTick: Equatable, Sendable {
    public let date: Date
    public let x: CGFloat
    public let isMajor: Bool
}
```

Generate a horizontal centerline for each visible primary interval and a vertical connector only when consecutive intervals touch in time. Choose tick intervals from `[300, 900, 1_800, 3_600, 7_200]` seconds so major labels remain roughly 60–100 points apart.

- [ ] **Step 4: Run geometry tests**

Expected: PASS with the Task 1 command.

- [ ] **Step 5: Commit render geometry**

```bash
git add SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddyTests/SleepTimelineGeometryTests.swift
git commit -m "feat: add stepped sleep path geometry"
```

---

### Task 4: Correct startup selection and add bounded night navigation

**Files:**
- Modify: `SleepDaddy/ViewModels/NightBrowserModel.swift`
- Modify: `SleepDaddyTests/NightBrowserModelTests.swift`

**Interfaces:**
- Produces: `canSelectPreviousNight`, `canSelectNextNight`.
- Produces: `selectPreviousNight()` and `selectNextNight()`.
- Changes: startup selection uses the last populated ascending night.

- [ ] **Step 1: Write failing model tests with a controllable clock/data fixture**

Add an injected `now: () -> Date` dependency to make night assembly deterministic. Create fixture intervals on two non-adjacent nights and assert:

```swift
@Test @MainActor func loadSelectsNewestPopulatedNight() async {
    let model = makeModel(
        now: july25Noon,
        intervals: [olderNightInterval, previousNightInterval]
    )
    await model.loadData()
    #expect(Calendar.current.isDate(model.selectedDate,
                                    inSameDayAs: previousNightDate))
}

@Test @MainActor func adjacentNavigationStopsAtBounds() async {
    let model = makeLoadedModel(now: july25Noon)
    while model.canSelectPreviousNight { model.selectPreviousNight() }
    let oldest = model.selectedDate
    model.selectPreviousNight()
    #expect(model.selectedDate == oldest)

    while model.canSelectNextNight { model.selectNextNight() }
    let newest = model.selectedDate
    model.selectNextNight()
    #expect(model.selectedDate == newest)
}
```

Add a no-data assertion that the selected date is the day before the injected current day.

- [ ] **Step 2: Run model tests and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightBrowserModelTests
```

Expected: FAIL because the clock dependency and adjacent-navigation API are missing, and the current implementation selects `.first(where:)`.

- [ ] **Step 3: Implement deterministic startup and navigation**

Store:

```swift
private let now: @Sendable () -> Date
```

Use it instead of direct `Date()` calls during load and assembly. Change populated selection to:

```swift
if let newest = assembledNights.last(where: { $0.hasSleepData }) {
    selectedDate = newest.date
} else {
    selectedDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
}
```

Find the selected index in the ascending `assembledNights` array for capability properties and navigation methods. On selection, clear `selectedInterval` and reset the viewport to the new night.

- [ ] **Step 4: Run model tests**

Expected: PASS with the command from Step 2.

- [ ] **Step 5: Commit startup and navigation**

```bash
git add SleepDaddy/ViewModels/NightBrowserModel.swift SleepDaddyTests/NightBrowserModelTests.swift
git commit -m "fix: open newest sleep night and bound navigation"
```

---

### Task 5: Replace the persistent night strip with the compact header

**Files:**
- Create: `SleepDaddy/Views/NightHeaderView.swift`
- Modify: `SleepDaddy/Views/ContentView.swift`
- Delete: `SleepDaddy/Views/MultiNightOverviewStrip.swift`
- Test: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: selected `AssembledNight`, `canSelectPreviousNight`, `canSelectNextNight`, previous/next closures, and calendar selection closure.
- Produces: a full-width header whose horizontal drag changes at most one night per gesture.

- [ ] **Step 1: Add a failing snapshot composition for the compact header**

Update the snapshot fixture to render `ContentView` in the loaded state and assert the reference image changes from the card strip to a single compact date/summary row. Keep the existing pixel-dimension assertion and create a new named reference, `sleep-timeline-redesign-reference.png`, so the previous artifact is not silently overwritten.

- [ ] **Step 2: Run the snapshot test and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Expected: FAIL because `NightHeaderView` and the compact-header composition do not exist.

- [ ] **Step 3: Implement `NightHeaderView`**

Build a header with:

```swift
NightHeaderView(
    night: night,
    canGoPrevious: model.canSelectPreviousNight,
    canGoNext: model.canSelectNextNight,
    onPrevious: model.selectPreviousNight,
    onNext: model.selectNextNight,
    onSelectDate: model.selectNight
)
```

Use 44-point arrow buttons, a center date button, and `DragGesture(minimumDistance: 24)`. Trigger only after horizontal translation exceeds 60 points and dominates vertical translation. Swipe left invokes next; swipe right invokes previous. Present a graphical `DatePicker` in a sheet constrained to `assembledNights.first!.date...assembledNights.last!.date`. Add `.accessibilityAction(named: "Previous night")` and `"Next night"`.

Remove `MultiNightOverviewStrip` from `ContentView` and delete its file.

- [ ] **Step 4: Record and inspect the new reference image**

Run the snapshot test in record mode using the existing project convention, open the resulting PNG, and confirm the header has no clipped text at default Dynamic Type. Then run the snapshot test normally.

Expected: PASS and visual inspection shows one compact row without the 14-card strip.

- [ ] **Step 5: Commit night header**

```bash
git add SleepDaddy/Views/NightHeaderView.swift SleepDaddy/Views/ContentView.swift SleepDaddy/Views/MultiNightOverviewStrip.swift SleepDaddyTests/SnapshotTests.swift SleepDaddyTests/ReferenceSnapshots
git commit -m "feat: add compact night navigation header"
```

---

### Task 6: Render the continuous path and wire live Maps-style gestures

**Files:**
- Create: `SleepDaddy/Views/TimelineGestureOverlay.swift`
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Modify: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `TimelineInteractionController`, `TimelineViewport`, step segments, ticks, and selected interval ID.
- Produces: continuous rendering during drag and magnification; commits `TimelineViewport` only after settling.

- [ ] **Step 1: Extend the visual test fixture with stage transitions**

Construct a snapshot night containing awake → core → deep → REM → awake, an `In Bed` interval, and one conflict. Assert the new reference visually contains a connected step path, fixed stage labels, time ticks, background In Bed band, and subtle conflict marker.

- [ ] **Step 2: Run snapshot tests and verify RED**

Run the Task 5 snapshot command.

Expected: FAIL because the canvas still draws disconnected rounded rectangles.

- [ ] **Step 3: Replace disconnected gesture state with the controller**

Use:

```swift
@State private var interaction: TimelineInteractionController
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Initialize/cancel it when the night or settled viewport changes. The body must construct geometry from `interaction.liveViewport`.

SwiftUI `MagnifyGesture.Value` exposes only the starting anchor, not the continuously moving centroid required by the approved behavior. Create a narrow `UIViewRepresentable` input overlay using `UIPinchGestureRecognizer` and `UIPanGestureRecognizer`; rendering remains entirely in SwiftUI `Canvas`.

The overlay API is:

```swift
struct TimelineGestureOverlay: UIViewRepresentable {
    let onInteractionBegan: () -> Void
    let onPanChanged: (_ translationX: CGFloat) -> Void
    let onPinchChanged: (_ scale: CGFloat, _ centroidX: CGFloat) -> Void
    let onInteractionEnded: (_ velocityX: CGFloat) -> Void
    let onTap: (_ location: CGPoint) -> Void
}
```

The coordinator installs pan, pinch, and tap recognizers, returns `true` from `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` for pan plus pinch, derives the live centroid with `pinch.location(in:)`, and prevents tap recognition after movement. The recognizers report state only; they must not transform the UIKit view.

Render:

- an `In Bed` background band;
- faint conflict ranges and warning markers;
- horizontal colored path segments;
- vertical connectors colored using the destination stage with reduced opacity;
- selected-segment emphasis;
- adaptive ticks and labels;
- fixed leading stage labels outside the moving plot region.

Use a `Transaction(animation: nil)` for every live update. Animate only the final settle, and skip inertia/settle animation when Reduce Motion is enabled.

- [ ] **Step 4: Make the detail timeline fill available height**

Remove `.frame(height: 280)`. Give `SelectedNightDetailView` a `GeometryReader` or flexible `VStack` so the canvas receives remaining height after header and navigator, with a minimum usable height of 320 points. Remove the outer vertical `ScrollView` for the loaded timeline path so it does not compete with timeline gestures; use an adaptive layout for compact height.

- [ ] **Step 5: Run targeted tests and inspect live interaction**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineInteractionControllerTests -only-testing:SleepDaddyTests/SleepTimelineGeometryTests -only-testing:SleepDaddyTests/SnapshotTests
```

Then launch the app in the iPhone 17 simulator and verify:

1. pinching visibly updates before release;
2. the time under the pinch anchor remains stationary;
3. a one-finger pan follows the finger;
4. a drag does not select an interval;
5. pinching outward returns to full night.

Expected: all tests PASS and all five manual checks succeed.

- [ ] **Step 6: Commit live timeline**

```bash
git add SleepDaddy/Views/TimelineGestureOverlay.swift SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddy/Views/SelectedNightDetailView.swift SleepDaddyTests/SnapshotTests.swift SleepDaddyTests/ReferenceSnapshots
git commit -m "feat: rebuild sleep timeline with live gestures"
```

---

### Task 7: Make the overview navigator continuously interactive

**Files:**
- Modify: `SleepDaddy/Views/SlimContextNavigator.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`

**Interfaces:**
- Consumes: complete-night geometry and the current live/settled `TimelineViewport`.
- Produces: `onUpdateViewport(TimelineViewport)` during viewport-window drag or track recenter.

- [ ] **Step 1: Add failing navigator math tests**

```swift
@Test func navigatorDragMovesViewportByFullNightRatio() {
    let moved = geometry.navigatorViewport(
        viewport,
        translatedBy: 40,
        navigatorWidth: 400
    )
    #expect(abs(moved.start.timeIntervalSince(viewport.start) - 4_320) < 0.001)
}

@Test func navigatorTapRecentersWithoutChangingDuration() {
    let moved = geometry.navigatorViewport(
        viewport,
        centeredAtX: 300,
        navigatorWidth: 400
    )
    #expect(moved.duration == viewport.duration)
    #expect(geometry.clamped(moved) == moved)
}
```

- [ ] **Step 2: Run geometry tests and verify RED**

Run the Task 1 geometry-test command.

Expected: FAIL because the navigator viewport methods are missing.

- [ ] **Step 3: Implement navigator math and view interaction**

Add the tested methods to `SleepTimelineGeometry`. In `SlimContextNavigator`, determine on touch-down whether the gesture begins inside the viewport window:

- inside: continuously translate the baseline viewport;
- outside: recenter once around the touched date, then allow continued drag;
- always clamp to the detected night.

Remove the inert `TapGesture` and the end-only callback. Keep a minimum 44-point interactive hit area even if the visible track is 24 points high.

- [ ] **Step 4: Run geometry tests and manually verify synchronization**

Run the Task 1 geometry-test command, then confirm dragging the overview updates the main path and time axis continuously.

Expected: PASS and no release-time jump.

- [ ] **Step 5: Commit navigator interaction**

```bash
git add SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddy/Views/SlimContextNavigator.swift SleepDaddy/Views/SelectedNightDetailView.swift SleepDaddyTests/SleepTimelineGeometryTests.swift
git commit -m "feat: make timeline overview directly manipulable"
```

---

### Task 8: Minimize filter/share/settings controls and remove duplicate branding

**Files:**
- Create: `SleepDaddy/Views/CompactSourceFilterButton.swift`
- Modify: `SleepDaddy/Views/ContentView.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Delete: `SleepDaddy/Views/SourceFilterView.swift`
- Modify: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: available source map, selected identifiers, and toggle callback.
- Produces: icon-only filter with active badge and source-selection sheet.

- [ ] **Step 1: Update the snapshot expectation for the minimal toolbar**

The loaded-state snapshot must contain exactly these actionable toolbar items:

- filter icon with active badge only when filtered;
- share icon;
- settings icon.

It must not contain the decorative moon, duplicate `SleepDaddy` label, Reset button, Share text, or always-visible source controls.

- [ ] **Step 2: Run snapshot test and verify RED**

Run the Task 5 snapshot command.

Expected: FAIL because the old toolbar and source view remain.

- [ ] **Step 3: Implement the compact filter sheet**

Build `CompactSourceFilterButton` with a `line.3.horizontal.decrease.circle` icon, a small badge when `selectedSourceIDs` is nonempty, and a 44-point hit target. Present a sheet with:

- sorted source names;
- checkmarks for selected identifiers;
- a clear-filter action;
- explicit explanation that no selected sources means all sources.

Move Share into the top toolbar as `square.and.arrow.up`, retaining existing render/share behavior. Keep Settings as `gearshape`. Remove the leading moon/title toolbar item, Reset button, visible source selector, and `SourceFilterView.swift`.

- [ ] **Step 4: Run snapshots and inspect accessibility labels**

Run the Task 5 snapshot command and inspect the accessibility hierarchy in the simulator.

Expected: PASS; controls are named “Filter sleep sources,” “Share timeline,” and “Settings,” with 44-point targets.

- [ ] **Step 5: Commit minimal controls**

```bash
git add SleepDaddy/Views/CompactSourceFilterButton.swift SleepDaddy/Views/ContentView.swift SleepDaddy/Views/SelectedNightDetailView.swift SleepDaddy/Views/SourceFilterView.swift SleepDaddyTests/SnapshotTests.swift SleepDaddyTests/ReferenceSnapshots
git commit -m "refactor: simplify sleep viewer controls"
```

---

### Task 9: Complete accessibility, layout, and regression verification

**Files:**
- Modify: `SleepDaddy/Views/NightHeaderView.swift`
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Modify: `SleepDaddyTests/SnapshotTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: all preceding components.
- Produces: release-ready behavior across supported accessibility and layout modes.

- [ ] **Step 1: Add final snapshots for layout variants**

Add deterministic snapshots for:

- iPhone 17 portrait, light mode;
- iPhone 17 portrait, dark mode;
- landscape;
- accessibility Dynamic Type;
- Reduce Motion environment.

Use the same fixed fixture dates and sleep records in every variant.

- [ ] **Step 2: Run the full unit suite before final polish**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: PASS. If a test fails, diagnose its root cause before changing production code.

- [ ] **Step 3: Finish adaptive and accessibility behavior**

Verify and correct:

- the date/summary shortens or wraps without overlapping arrows;
- chronological interval VoiceOver elements still activate the inspector;
- colors are accompanied by stage labels;
- header exposes previous/next accessibility actions;
- icon-only controls have labels and hints;
- Reduce Motion eliminates inertia and directional slide transitions;
- overview remains reachable and visible above the safe area;
- no large unused region remains below the timeline.

Update `README.md` to describe the continuous stepped path, Maps-style direct manipulation, compact night navigation, and newest populated night startup.

- [ ] **Step 4: Regenerate and build**

Run:

```bash
xcodegen generate
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: generation succeeds, build succeeds, and all tests pass. Do not stage the generated project or Info.plist.

- [ ] **Step 5: Perform final hands-on acceptance pass**

On iPhone 17 portrait and landscape:

1. launch selects the newest populated sleep night;
2. header arrows and edge-to-edge header swipes navigate in correct directions;
3. date tap presents non-adjacent selection;
4. pinch and pan update continuously;
5. pinch remains anchored;
6. inertia is brief and predictable;
7. overview drag updates continuously;
8. outward pinch restores full night;
9. primary stages form one connected path;
10. filter, share, and settings remain accessible without persistent clutter.

- [ ] **Step 6: Commit final verification and documentation**

```bash
git add README.md SleepDaddy SleepDaddyTests
git commit -m "test: verify redesigned sleep viewing experience"
```
