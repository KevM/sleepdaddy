# Immersive Landscape Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the sleep timeline substantially more vertical room on landscape phones at both regular and accessibility Dynamic Type sizes while preserving all night-navigation behavior.

**Architecture:** Resolve a small, testable layout mode from SwiftUI's vertical size class at the screen-composition boundary. In compact-height layouts, place a date-picker button and separate duration label in the principal toolbar while keeping previous/next arrows at the canvas edges; retain the existing standalone portrait header. The canvas and its geometry remain unchanged; only its parent composition changes.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`Testing`), UIKit-hosted composition rendering, XcodeGen-managed iOS 26 project.

## Global Constraints

- HealthKit remains read-only.
- Do not commit `SleepDaddy.xcodeproj` or generated `Info.plist` files.
- Portrait composition remains unchanged.
- Do not change sleep-stage geometry, colors, filtering, data loading, or export rendering.
- Keep settings, sharing, and source filtering in the navigation toolbar.
- Preserve 44-point previous/next hit targets, the existing date picker, VoiceOver metadata, custom accessibility actions, and timeline gestures.
- Dynamic Type stays enabled for the date and duration; do not globally cap it to make the layout fit.

---

## File Map

- `SleepDaddy/Views/ContentView.swift`: Resolves standard versus immersive composition from `verticalSizeClass`, suppresses the standalone header/divider in immersive mode, and passes layout context to the detail view.
- `SleepDaddy/Views/NightHeaderView.swift`: Adds a presentation enum and applies either the existing standalone background/padding or a compact material overlay treatment while retaining one behavior implementation.
- `SleepDaddy/Views/SelectedNightDetailView.swift`: Overlays night navigation on the timeline in immersive mode, gives the canvas layout priority and a useful minimum height, and adds scrolling only when accessibility content cannot fit.
- `SleepDaddyTests/SnapshotTests.swift`: Tests mode resolution and renders full loaded landscape compositions at regular and accessibility Dynamic Type sizes.

### Task 1: Testable Responsive Layout Selection

**Files:**
- Modify: `SleepDaddy/Views/ContentView.swift`
- Test: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Produces: `enum SelectedNightLayoutMode: Equatable { case standard, immersiveLandscape }`
- Produces: `static func resolve(verticalSizeClass: UserInterfaceSizeClass?) -> SelectedNightLayoutMode`
- Consumes: SwiftUI `UserInterfaceSizeClass.compact` for a phone in landscape.

- [ ] **Step 1: Write the failing layout-selection test**

Add to `SnapshotTests`:

```swift
@Test func compactHeightSelectsImmersiveLandscapeLayout() {
    #expect(SelectedNightLayoutMode.resolve(verticalSizeClass: .compact) == .immersiveLandscape)
    #expect(SelectedNightLayoutMode.resolve(verticalSizeClass: .regular) == .standard)
    #expect(SelectedNightLayoutMode.resolve(verticalSizeClass: nil) == .standard)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/compactHeightSelectsImmersiveLandscapeLayout
```

Expected: compilation fails because `SelectedNightLayoutMode` does not exist.

- [ ] **Step 3: Add the minimal resolver**

Add near `ContentView`:

```swift
enum SelectedNightLayoutMode: Equatable {
    case standard
    case immersiveLandscape

    static func resolve(verticalSizeClass: UserInterfaceSizeClass?) -> SelectedNightLayoutMode {
        verticalSizeClass == .compact ? .immersiveLandscape : .standard
    }
}
```

- [ ] **Step 4: Re-run the focused test**

Expected: PASS with no warnings introduced by this change.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Views/ContentView.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "test: define immersive landscape layout selection"
```

### Task 2: Shared Standalone and Overlay Night Header

**Files:**
- Modify: `SleepDaddy/Views/NightHeaderView.swift`
- Test: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Produces: `NightHeaderView.Presentation` with `.standalone` and `.timelineOverlay`.
- Produces: initializer argument `presentation: Presentation = .standalone`.
- Consumes: existing date formatting, picker binding, callbacks, swipe gesture, and accessibility actions without duplication.

- [ ] **Step 1: Write the failing overlay-header test**

```swift
@Test @MainActor func timelineOverlayHeaderRendersAtAccessibilitySize() {
    let night = makeFixtureNight()
    let header = NightHeaderView(
        night: night,
        canGoPrevious: true,
        canGoNext: true,
        presentation: .timelineOverlay,
        onPrevious: {},
        onNext: {},
        onSelectDate: { _ in }
    )
    .frame(width: 520, height: 82)
    .environment(\.dynamicTypeSize, .accessibility2)
    .environment(\.locale, Locale(identifier: "en_US"))
    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

    renderComposition(
        of: header,
        named: "timeline overlay header accessibility",
        expecting: CGSize(width: 520, height: 82)
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/timelineOverlayHeaderRendersAtAccessibilitySize
```

Expected: compilation fails because `Presentation.timelineOverlay` and the initializer parameter do not exist.

- [ ] **Step 3: Add the shared presentation API**

Inside `NightHeaderView`, add:

```swift
enum Presentation {
    case standalone
    case timelineOverlay
}

let presentation: Presentation
```

Add `presentation: Presentation = .standalone` to the initializer and assign it. Keep one shared button hierarchy, sheet, gesture, and accessibility implementation. Apply the current padding/background for `.standalone`; for `.timelineOverlay`, use:

```swift
content
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
```

Allow the central date/duration stack to wrap at accessibility sizes, retain each arrow's existing `44 x 44` frame, and do not add a Dynamic Type cap.

- [ ] **Step 4: Run both header tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/testNightHeaderSnapshotComposition -only-testing:SleepDaddyTests/SnapshotTests/timelineOverlayHeaderRendersAtAccessibilitySize
```

Expected: both PASS; the default presentation preserves the existing header.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Views/NightHeaderView.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: add timeline overlay night header"
```

### Task 3: Immersive Compact-Height Composition

**Files:**
- Modify: `SleepDaddy/Views/ContentView.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Test: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: `SelectedNightLayoutMode.resolve(verticalSizeClass:)` from Task 1.
- Consumes: `NightHeaderView.Presentation.timelineOverlay` from Task 2.
- Produces: `SelectedNightDetailView.init(model:layoutMode:dateRange:)`.
- Produces: `SelectedNightDetailView.immersiveTimelineHeight(availableHeight:navigatorHeight:) -> CGFloat`, which fills spare height but never returns less than 220 points.

- [ ] **Step 1: Write the failing minimum-height contract test**

```swift
@Test func immersiveTimelineFillsAvailableHeightWithoutCollapsing() {
    #expect(
        SelectedNightDetailView.immersiveTimelineHeight(
            availableHeight: 320,
            navigatorHeight: 64
        ) == 250
    )
    #expect(
        SelectedNightDetailView.immersiveTimelineHeight(
            availableHeight: 250,
            navigatorHeight: 64
        ) == 220
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/immersiveTimelineFillsAvailableHeightWithoutCollapsing
```

Expected: compilation fails because `immersiveTimelineHeight(availableHeight:navigatorHeight:)` does not exist.

- [ ] **Step 3: Make `ContentView` choose the composition**

Add `@Environment(\.verticalSizeClass) private var verticalSizeClass`. In the loaded state resolve:

```swift
let layoutMode = SelectedNightLayoutMode.resolve(verticalSizeClass: verticalSizeClass)
```

Render the existing standalone `NightHeaderView`, divider, and vertical detail padding only when `layoutMode == .standard`. Pass `layoutMode` and the existing computed `dateRange` to `SelectedNightDetailView`. Immersive mode uses the full remaining content height.

- [ ] **Step 4: Add the immersive detail composition**

In `SelectedNightDetailView`, add the new initializer inputs and the tested height policy:

```swift
static func immersiveTimelineHeight(
    availableHeight: CGFloat,
    navigatorHeight: CGFloat
) -> CGFloat {
    max(220, availableHeight - navigatorHeight - 6)
}
```

Extract the current canvas and navigator into private builders so callbacks and live viewport behavior are identical in both modes. Keep the existing standard `VStack` unchanged. For immersive mode, use:

```swift
GeometryReader { proxy in
    ScrollView(.vertical) {
        VStack(spacing: 6) {
            timelineCanvas(night: night)
                .frame(height: Self.immersiveTimelineHeight(
                    availableHeight: proxy.size.height,
                    navigatorHeight: 64
                ))
                .overlay(alignment: .top) {
                    NightHeaderView(
                        night: night,
                        canGoPrevious: model.canSelectPreviousNight,
                        canGoNext: model.canSelectNextNight,
                        dateRange: dateRange,
                        presentation: .timelineOverlay,
                        onPrevious: model.selectPreviousNight,
                        onNext: model.selectNextNight,
                        onSelectDate: model.selectNight
                    )
                    .padding(.horizontal, 84)
                    .padding(.top, 4)
                }

            contextNavigator(night: night)
        }
    }
    .scrollBounceBehavior(.basedOnSize)
}
```

The geometry-based height fills the visible detail area during normal landscape use and makes the scroll view taller only when the 220-point minimum cannot fit. The horizontal inset keeps overlay controls away from the plot's edge gestures. Keep empty and loading states functional without requiring an overlay.

- [ ] **Step 5: Run the contract and portrait regression tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/immersiveTimelineFillsAvailableHeightWithoutCollapsing -only-testing:SleepDaddyTests/SnapshotTests/testSnapshotPortraitLightMode -only-testing:SleepDaddyTests/SnapshotTests/testSnapshotDynamicType
```

Expected: all PASS and portrait render dimensions remain unchanged.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Views/ContentView.swift SleepDaddy/Views/SelectedNightDetailView.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: prioritize timeline in landscape"
```

### Task 4: Full Landscape Regression Coverage and Verification

**Files:**
- Modify: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: loaded `ContentView` and compact vertical size class from Tasks 1–3.
- Produces: hosted landscape regression tests at `852 x 393` points.

- [ ] **Step 1: Add a loaded fixture-model helper**

```swift
@MainActor
private func makeLoadedFixtureModel(suiteName: String) async -> NightBrowserModel {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = NightBrowserModel(
        store: FixtureSleepStore(),
        preferencesStore: PreferencesStore(userDefaults: defaults)
    )
    await model.loadData()
    return model
}
```

- [ ] **Step 2: Add regular and accessibility hosted tests**

```swift
@Test @MainActor func loadedLandscapeKeepsImmersiveTimeline() async throws {
    let model = await makeLoadedFixtureModel(suiteName: "SnapshotTests.LoadedLandscape")
    let content = ContentView(model: model)
        .environment(\.verticalSizeClass, .compact)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

    try await assertHostedComposition(
        of: content,
        named: "loaded landscape",
        width: 852,
        height: 393,
        isReady: { model.appState == .loaded }
    )
}

@Test @MainActor func loadedLandscapeAccessibilityKeepsImmersiveTimeline() async throws {
    let model = await makeLoadedFixtureModel(suiteName: "SnapshotTests.LoadedLandscapeAccessibility")
    let content = ContentView(model: model)
        .environment(\.verticalSizeClass, .compact)
        .environment(\.dynamicTypeSize, .accessibility2)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

    try await assertHostedComposition(
        of: content,
        named: "loaded landscape accessibility",
        width: 852,
        height: 393,
        isReady: { model.appState == .loaded }
    )
}
```

- [ ] **Step 3: Run the landscape tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests/loadedLandscapeKeepsImmersiveTimeline -only-testing:SleepDaddyTests/SnapshotTests/loadedLandscapeAccessibilityKeepsImmersiveTimeline
```

Expected: both PASS and rasterize at `1704 x 786` pixels.

- [ ] **Step 4: Run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Build the app**

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Review scope**

```bash
git status --short
git diff --check
git diff --stat
```

Expected: only the three Swift source/test files are modified; no generated project, plist, or unrelated user files are included.

- [ ] **Step 7: Commit coverage**

```bash
git add SleepDaddyTests/SnapshotTests.swift
git commit -m "test: cover immersive landscape timeline"
```


### Task 5: Move Landscape Date and Duration into the Toolbar

**Files:**
- Create: `SleepDaddy/Views/LandscapeNightToolbarView.swift`
- Create: `SleepDaddy/Views/TimelineNightNavigationControls.swift`
- Modify: `SleepDaddy/Views/ContentView.swift`
- Modify: `SleepDaddy/Views/NightHeaderView.swift`
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Modify: `SleepDaddyTests/SnapshotTests.swift`

**Interfaces:**
- Produces: `LandscapeNightToolbarView`, containing one compact date-picker button and one separate, non-interactive duration label.
- Produces: `LandscapeNightToolbarPresencePreferenceKey`, used by hosted tests to observe the rendered toolbar component.
- Produces: `TimelineNightNavigationControls`, containing only the 44-point previous/next edge buttons and accessibility actions.
- Consumes: existing `NightHeaderView.formattedDate(_:locale:timeZone:)`, date-range selection semantics, model callbacks, and `AccessibilityHelpers.formattedTimeInterval`.
- Removes: `NightHeaderView.Presentation.timelineOverlay` and the immersive timeline's date-header overlay. Portrait retains `.standalone` behavior unchanged.

- [ ] **Step 1: Write failing semantic toolbar tests**

Update the two loaded landscape hosted tests so their ready state captures and requires all of these invariants:

```swift
#expect(layoutMode == .immersiveLandscape)
#expect(landscapeToolbarIsPresent)
#expect(headerPresentation == nil)
#expect(timelineBounds.height >= 220)
```

Add a focused composition test that renders `LandscapeNightToolbarView` and captures two separate semantic elements: an interactive date picker and a non-interactive duration label. Assert the date button accessibility label contains only the formatted date and its hint says it chooses a date; assert the duration label has its own accessibility label.

Retain the hosted portrait test's `.standard` and `.standalone` assertions.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:'SleepDaddyTests/SnapshotTests/loadedLandscapeKeepsImmersiveTimeline()' -only-testing:'SleepDaddyTests/SnapshotTests/loadedLandscapeAccessibilityKeepsImmersiveTimeline()' -only-testing:'SleepDaddyTests/SnapshotTests/landscapeToolbarSeparatesDateAndDuration()'
```

Expected: compilation fails because `LandscapeNightToolbarView` and its semantic presence signal do not exist, and the current immersive composition still reports `.timelineOverlay`.

- [ ] **Step 3: Extract shared formatting without changing portrait**

Make `NightHeaderView.durationFormatted` available through an internal static helper:

```swift
static func formattedDuration(for night: AssembledNight) -> String {
    night.hasSleepData
        ? AccessibilityHelpers.formattedTimeInterval(night.summary.totalSleepDuration)
        : "No Data"
}
```

Keep the existing portrait date button's combined date/duration presentation and accessibility label unchanged by calling the helper from its existing layout.

- [ ] **Step 4: Implement the standalone landscape toolbar component**

Create `LandscapeNightToolbarView.swift`. It accepts:

```swift
let night: AssembledNight
let dateRange: ClosedRange<Date>?
let onSelectDate: (Date) -> Void
```

Its body is a compact `HStack` in the principal toolbar position:

- A date-only `Button` showing `NightHeaderView.formattedDate` and a small downward chevron.
- A separate accent-colored `Text` showing `NightHeaderView.formattedDuration(for:)`.
- The date button opens the same medium graphical date-picker sheet and dismisses after selection.
- The date button accessibility label is only the formatted date and its hint is “Double tap to choose a date.”
- The duration label has an independent accessibility label such as “Sleep duration, 10 hours 54 minutes.”
- Emit `LandscapeNightToolbarPresencePreferenceKey = true` from the rendered component for hosted semantic verification.
- Use natural toolbar sizing; do not add `maxWidth: .infinity`, fixed screen-width frames, or a Dynamic Type cap.

- [ ] **Step 5: Put the landscape component in the principal toolbar**

In `ContentView`, compute the current layout mode and date range once in private properties usable by both content and toolbar. Keep `.navigationTitle("SleepDaddy")` for standard mode and non-loaded states. Add:

```swift
if currentLayoutMode == .immersiveLandscape,
   let night = model.selectedAssembledNight {
    ToolbarItem(placement: .principal) {
        LandscapeNightToolbarView(
            night: night,
            dateRange: selectedDateRange,
            onSelectDate: model.selectNight
        )
    }
}
```

Do not modify the existing trailing filter/share/settings `ToolbarItem`.

- [ ] **Step 6: Replace the timeline header overlay with edge navigation**

Create `TimelineNightNavigationControls.swift` with the same previous/next button actions, disabled appearance, 44-point hit targets, accessibility labels, hints, and custom accessibility actions currently used by `NightHeaderView`. Its visual body is:

```swift
HStack {
    previousButton
    Spacer()
    nextButton
}
```

In immersive loaded detail, remove the `NightHeaderView(... presentation: .timelineOverlay ...)` overlay and replace it with `TimelineNightNavigationControls`, vertically centered over the timeline with narrow edge-only hit regions. The canvas remains interactive everywhere except the two 44-point button targets.

For immersive empty nights, show the same edge navigation controls with the empty state rather than restoring the full standalone header. Keep loading behavior unchanged.

Remove `.timelineOverlay` from `NightHeaderView.Presentation` and delete its material/shadow styling. `NightHeaderView` remains the portrait-only standalone header.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run the command from Step 2 plus:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:'SleepDaddyTests/SnapshotTests/loadedPortraitUsesStandardComposition()' -only-testing:'SleepDaddyTests/SnapshotTests/immersiveEmptyNightUsesStandaloneNavigationHeader()'
```

Rename the empty-night test to reflect edge navigation rather than standalone-header behavior and assert the landscape toolbar is present while `NightHeaderPresentationPreferenceKey` remains nil.

Expected: all selected tests PASS. Loaded landscape reports toolbar presence, no timeline header overlay, and timeline height at least 220 points. Portrait still reports `.standalone`.

- [ ] **Step 8: Run full verification**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
git diff --check
git status --short
```

Expected: 109 or more tests pass, build succeeds, and no generated project/plist or unrelated user files are staged.

- [ ] **Step 9: Commit**

```bash
git add SleepDaddy/Views/LandscapeNightToolbarView.swift SleepDaddy/Views/TimelineNightNavigationControls.swift SleepDaddy/Views/ContentView.swift SleepDaddy/Views/NightHeaderView.swift SleepDaddy/Views/SelectedNightDetailView.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: move landscape date into toolbar"
```
