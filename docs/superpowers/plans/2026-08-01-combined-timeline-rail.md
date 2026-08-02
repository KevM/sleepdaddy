# Combined Timeline Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the separate configured-time navigator with one compact, interactive 44-point rail that retains current-viewport time labels in portrait and landscape.

**Architecture:** Extract the visible-time labels and full-night viewport handle into a focused `CombinedTimelineRail` aligned to the timeline plot. `SleepTimelineCanvas` owns the rail and continues drawing vertical tick guidelines in its plot, while `SelectedNightDetailView` stops composing an external navigator and gives the reclaimed height to the canvas.

**Tech Stack:** Swift 6, SwiftUI, iOS 26+, Swift Testing, existing `SleepTimelineGeometry` and `TimelineViewport` types.

## Global Constraints

- HealthKit remains read-only; this feature does not add or change HealthKit writes.
- The combined rail is exactly 44 points high: adaptive visible-window labels above a visually 10-point minimap track.
- The combined rail is aligned to the plot region and excludes the fixed 68-point stage-label column.
- The minimap remains interactive with tap-to-recenter and drag-to-pan behavior.
- The minimap shows no configured timeline start/end, core-window, or `Extended` text.
- Portrait and landscape use the same combined rail.
- The minimap accessibility label retains the full navigable timeline start and end.
- Timeline pinch, pan, inertia, interval selection, clamping, and data models remain unchanged.
- Unit tests use `import Testing`, `@Test`, and `#expect(...)`.
- Do not commit `SleepDaddy.xcodeproj` or generated `Info.plist` files.

---

### Task 1: Build the combined visible-time rail

**Files:**
- Create: `SleepDaddy/Views/CombinedTimelineRail.swift`
- Modify: `SleepDaddy/Layout/SleepTimelineGeometry.swift`
- Modify: `SleepDaddyTests/SleepTimelineGeometryTests.swift`
- Modify: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `AssembledNight`, `TimelineViewport`, `SleepTimelineGeometry.timeTicks(calendar:)`, `SleepTimelineGeometry.timeLabelLayouts(for:)`, `SleepTimelineGeometry.navigatorXRatio(for:)`, and both `navigatorViewport` overloads.
- Produces: `CombinedTimelineRail(night:viewport:onUpdateViewport:)`, `SleepTimelineGeometry.timeAxisHeight == 44`, `SleepTimelineGeometry.timeLabelBandHeight == 20`, and `SleepTimelineGeometry.navigatorTrackHeight == 10`.

- [ ] **Step 1: Add failing geometry assertions for the combined rail dimensions**

Append to `SleepDaddyTests/SleepTimelineGeometryTests.swift`:

```swift
@Test func combinedTimelineRailUsesOneCompactTouchTarget() {
    #expect(SleepTimelineGeometry.timeAxisHeight == 44)
    #expect(SleepTimelineGeometry.timeLabelBandHeight == 20)
    #expect(SleepTimelineGeometry.navigatorTrackHeight == 10)
}
```

- [ ] **Step 2: Run the focused geometry test and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

Expected: compilation fails because `timeLabelBandHeight` and `navigatorTrackHeight` do not exist, and the old axis height is 28.

- [ ] **Step 3: Define the shared rail dimensions**

In `SleepDaddy/Layout/SleepTimelineGeometry.swift`, replace the old axis constant with:

```swift
public static let timeAxisHeight: CGFloat = 44.0
public static let timeLabelBandHeight: CGFloat = 20.0
public static let navigatorTrackHeight: CGFloat = 10.0
```

Do not change `usablePlotHeight()` beyond allowing it to consume the revised `timeAxisHeight`.

- [ ] **Step 4: Run the focused geometry test and verify GREEN**

Run the command from Step 2.

Expected: `SleepTimelineGeometryTests` passes.

- [ ] **Step 5: Add a failing render test for the standalone combined rail**

In `SleepDaddyTests/SnapshotTests.swift`, add this test beside the existing navigator render coverage:

```swift
@Test @MainActor func combinedTimelineRailRendersAtItsSpecifiedHeight() {
    let night = makeFixtureNight()
    let rail = CombinedTimelineRail(
        night: night,
        viewport: TimelineViewport(
            normalizing: night.detectedStart,
            end: night.detectedEnd
        ),
        onUpdateViewport: { _ in }
    )
    .frame(width: 700, height: SleepTimelineGeometry.timeAxisHeight)
    .environment(\.locale, Locale(identifier: "en_US"))
    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

    renderComposition(
        of: rail,
        named: "combined timeline rail",
        expecting: CGSize(width: 700, height: 44)
    )
}
```

- [ ] **Step 6: Run the new render test and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/combinedTimelineRailRendersAtItsSpecifiedHeight
```

Expected: compilation fails because `CombinedTimelineRail` does not exist.

- [ ] **Step 7: Implement the focused combined rail view**

Create `SleepDaddy/Views/CombinedTimelineRail.swift` with this structure:

```swift
import SwiftUI

struct CombinedTimelineRail: View {
    let night: AssembledNight
    let viewport: TimelineViewport
    let onUpdateViewport: (TimelineViewport) -> Void

    @State private var baselineViewport: TimelineViewport?
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        GeometryReader { proxy in
            let geometry = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: viewport,
                canvasWidth: proxy.size.width,
                canvasHeight: proxy.size.height
            )

            VStack(spacing: 0) {
                visibleTimeLabels(geometry: geometry)
                    .frame(height: SleepTimelineGeometry.timeLabelBandHeight)

                navigator(geometry: geometry, width: proxy.size.width)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: SleepTimelineGeometry.timeAxisHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Timeline navigator from \(formatted(night.timelineStart)) to \(formatted(night.timelineEnd))"
        )
        .accessibilityHint("Adjusts the visible time range")
        .accessibilityAdjustableAction { direction in
            adjustViewport(direction)
        }
    }

    private func adjustViewport(_ direction: AccessibilityAdjustmentDirection) {
        let sign: Double
        switch direction {
        case .increment: sign = 1
        case .decrement: sign = -1
        @unknown default: return
        }
        let geometry = SleepTimelineGeometry(
            totalStart: night.timelineStart,
            totalEnd: night.timelineEnd,
            viewport: viewport,
            canvasWidth: 1,
            canvasHeight: SleepTimelineGeometry.timeAxisHeight
        )
        onUpdateViewport(
            geometry.clamped(viewport.shifted(by: viewport.duration * 0.1 * sign))
        )
    }
}
```

Implement `visibleTimeLabels(geometry:)` as a `Canvas` that:

- calls `geometry.timeTicks(calendar: calendar)`;
- resolves only major-tick `Text` values formatted as `h:mm a` with `timeZone`;
- measures them and passes `TimelineTimeLabelCandidate` values to `timeLabelLayouts(for:)`; and
- draws retained labels centered inside the 20-point label band.

Implement `navigator(geometry:width:)` with:

- the existing quaternary capsule track;
- the existing accent-colored viewport handle, with a minimum visual width equal to `navigatorTrackHeight`;
- no core-window fill and no textual labels;
- a `DragGesture(minimumDistance: 0)` using the existing inside-handle baseline, tap recenter, translated drag, and baseline reset logic from `SlimContextNavigator`; and
- a transparent full-height `contentShape(Rectangle())`, so the rail provides the touch target while the capsule remains 10 points tall.

Use a private formatter helper that sets both locale and `timeZone`; do not add configured/core/extended visual text.

- [ ] **Step 8: Run the component and geometry tests and verify GREEN**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepTimelineGeometryTests -only-testing:SleepDaddyTests/SnapshotTests/combinedTimelineRailRendersAtItsSpecifiedHeight
```

Expected: both selected suites pass.

- [ ] **Step 9: Commit Task 1**

```bash
git add SleepDaddy/Views/CombinedTimelineRail.swift SleepDaddy/Layout/SleepTimelineGeometry.swift SleepDaddyTests/SleepTimelineGeometryTests.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: add combined timeline rail"
```

---

### Task 2: Integrate the rail and reclaim navigator height

**Files:**
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Delete: `SleepDaddy/Views/SlimContextNavigator.swift`
- Modify: `SleepDaddy/Views/ContentView.swift`
- Modify: `SleepDaddyTests/SnapshotTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `CombinedTimelineRail(night:viewport:onUpdateViewport:)` and the 44-point `SleepTimelineGeometry.timeAxisHeight` from Task 1.
- Produces: `SelectedNightDetailView.immersiveTimelineHeight(availableHeight:)` and one combined rail owned by every interactive `SleepTimelineCanvas`.

- [ ] **Step 1: Write failing composition and height tests**

Replace `immersiveTimelineFillsAvailableHeightWithoutCollapsing()` in `SleepDaddyTests/SnapshotTests.swift` with:

```swift
@Test func immersiveTimelineUsesAllAvailableHeightWithoutExternalNavigator() {
    #expect(
        SelectedNightDetailView.immersiveTimelineHeight(availableHeight: 320) == 320
    )
    #expect(
        SelectedNightDetailView.immersiveTimelineHeight(availableHeight: 210) == 220
    )
}
```

Extend `HostedTimelinePresentationRecorder` and `HostedTimelinePresentationMetrics` with `combinedRailIsPresent`, then add a preference capture following the existing toolbar-presence pattern. Add assertions:

```swift
#expect(metrics.combinedRailIsPresent)
```

to `loadedLandscapeKeepsImmersiveTimeline()`, `loadedLandscapeAccessibilityKeepsImmersiveTimeline()`, and `loadedPortraitUsesStandardComposition()`.

Add a production preference key beside the other composition-test keys in `ContentView.swift`:

```swift
struct CombinedTimelineRailPresencePreferenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
```

Capture it in `assertHostedComposition` exactly as the existing layout and toolbar preferences are captured.

- [ ] **Step 2: Run the focused composition tests and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/immersiveTimelineUsesAllAvailableHeightWithoutExternalNavigator -only-testing:SleepDaddyTests/SnapshotTests/loadedLandscapeKeepsImmersiveTimeline -only-testing:SleepDaddyTests/SnapshotTests/loadedLandscapeAccessibilityKeepsImmersiveTimeline -only-testing:SleepDaddyTests/SnapshotTests/loadedPortraitUsesStandardComposition
```

Expected: compilation fails because the old height helper requires `navigatorHeight`, and rail-presence assertions fail because the canvas has not emitted the preference.

- [ ] **Step 3: Integrate the combined rail into the canvas**

In `SleepDaddy/Views/SleepTimelineCanvas.swift`:

1. Keep the existing outer 68-point stage-label column.
2. Change the plot side to a `VStack(spacing: 0)` containing:
   - the existing plot `ZStack`, framed to `max(1, totalHeight - SleepTimelineGeometry.timeAxisHeight)`; and
   - `CombinedTimelineRail`, passed `interaction.liveViewport` and the existing `onUpdateViewport` callback.
3. Construct the outer interaction geometry with `canvasHeight` equal to that reduced plot height, so lane centers, hit testing, and gestures use the same coordinate space as the plot.
4. Keep vertical tick guidelines in the plot `Canvas`, but remove time-label measurement and drawing from that canvas.
5. Draw guidelines to the plot's full height rather than subtracting the rail height a second time.
6. Emit `.preference(key: CombinedTimelineRailPresencePreferenceKey.self, value: true)` from the combined rail.

The rail callback must use the same committed update path:

```swift
CombinedTimelineRail(night: night, viewport: liveViewport) { newViewport in
    onUpdateViewport(newViewport.start, newViewport.end)
}
```

Do not place the timeline's `TimelineGestureOverlay` over the rail; it remains limited to the plot `ZStack`, preventing gesture competition.

- [ ] **Step 4: Remove the external navigator from both detail compositions**

In `SleepDaddy/Views/SelectedNightDetailView.swift`:

- remove `contextNavigator(night:)` and both call sites;
- make standard detail contain only the canvas for a loaded night;
- replace the height helper with:

```swift
nonisolated static func immersiveTimelineHeight(availableHeight: CGFloat) -> CGFloat {
    max(220, availableHeight)
}
```

- frame immersive canvas using only `proxy.size.height`; and
- remove the now-unnecessary inner `VStack`, external spacing, and vertical `ScrollView` when content cannot exceed the provided geometry.

Delete `SleepDaddy/Views/SlimContextNavigator.swift`. XcodeGen discovers source files automatically, so `project.yml` does not need a source-list change.

- [ ] **Step 5: Update user-facing documentation**

Replace the README feature bullet for `Slim Context Navigator` with:

```markdown
- **Combined Timeline Rail**: Adaptive labels describe the visible window while a compact interactive mini-map preserves full-night context without duplicating configured-time legends.
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: all selected tests pass; both portrait and landscape report the combined rail, and immersive height uses all available space.

- [ ] **Step 7: Run the full unit test suite**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: all tests pass with zero failures.

- [ ] **Step 8: Build the app**

Run:

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit Task 2**

```bash
git add SleepDaddy/Views/SleepTimelineCanvas.swift SleepDaddy/Views/SelectedNightDetailView.swift SleepDaddy/Views/SlimContextNavigator.swift SleepDaddy/Views/ContentView.swift SleepDaddyTests/SnapshotTests.swift README.md
git commit -m "feat: combine timeline labels and navigator"
```
