# Brief Awake Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in filter that hides awake intervals of 60 seconds or less from the timeline drawing, while every reported total keeps being computed from the unfiltered data.

**Architecture:** A pure `AwakeSpikeSmoother` removes brief awake intervals from a lane and hands their time to the neighbouring interval, so the drawn path stays continuous. `NightAssembler` runs it *after* `summary` is calculated and stores the result as a second lane, `AssembledNight.displayLaneIntervals`, which the canvas draws, hit-tests, and describes to VoiceOver. Summaries, stage percentages, and night bounds are structurally unable to see the filter.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-27-brief-awake-filter-design.md`

---

## Background for the implementer

`NormalizedSleepInterval` (`SleepDaddy/Models/NormalizedSleepInterval.swift`) is an immutable
struct — every stored property is `let`. To "extend" one you construct a new value copying the
other fields. It has `duration: TimeInterval` and is `Hashable`, so arrays of it compare with
`==`.

`NightAssembler.assembleNight` builds `primaryLaneIntervals` by slicing every raw interval at
its boundaries, picking a winner per slice, then coalescing adjacent slices that share stage
and `sourceIdentifier` (`SleepDaddy/Services/NightAssembler.swift:196-225`). The lane it
produces is sorted by `startDate` and contiguous. `calculateSummary` runs on that lane at line
126 — the new smoothing must run *after* that call, never before.

`SleepTimelineGeometry.stepSegments` (`SleepDaddy/Layout/SleepTimelineGeometry.swift:316`)
draws the vertical connector between two intervals only when they touch in time within a
millisecond. This is why the smoother reassigns a hidden spike's time instead of just deleting
it: a deleted spike would leave a one-minute horizontal hole *and* two missing connectors.

`PreferencesStore.load()` (`SleepDaddy/Services/PreferencesStore.swift:12`) decodes with
`try?` and returns `.default` on any error. Swift's synthesized `Codable` conformance does not
fall back to a property's default value when a key is missing, so adding a field to
`SleepPreferences` without a custom `init(from:)` would reset every existing install's core
window, source selection, and exclusion list. Task 2 handles this.

**Important build note:** `project.yml` globs sources by directory, so a newly created
`.swift` file is invisible to Xcode until `xcodegen generate` runs. Tasks 1 and 2 include that
step. Do not commit `SleepDaddy.xcodeproj` or `Info.plist` — they are generated.

**Snapshot tests** compare rendered PNGs against references in
`SleepDaddyTests/ReferenceSnapshots/`. When a reference file is missing, the test writes it
and passes. Existing references are *not* expected to change in this plan, because the
preference defaults to off and the display lane is then identical to the primary lane. If an
existing snapshot fails, that is a real regression — investigate, do not regenerate.

**Test command** (whole suite):

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Append `-only-testing:SleepDaddyTests/SuiteName` to run one suite.

---

## File Structure

- **Create** `SleepDaddy/Services/AwakeSpikeSmoother.swift` — the lane transformation. A pure
  value type with no dependency on preferences or views, so it is testable in isolation and
  the assembler decides only *whether* to apply it.
- **Create** `SleepDaddyTests/AwakeSpikeSmootherTests.swift` — unit tests for that transform.
- **Modify** `SleepDaddy/Models/SleepPreferences.swift` — new `hidesBriefAwakes` flag plus the
  migration-safe decoder.
- **Modify** `SleepDaddy/Models/AssembledNight.swift` — new `displayLaneIntervals` property.
- **Modify** `SleepDaddy/Services/NightAssembler.swift` — populate the new lane.
- **Modify** `SleepDaddy/Views/SleepTimelineCanvas.swift` — draw, hit-test, and describe from
  the display lane.
- **Modify** `SleepDaddy/ViewModels/NightBrowserModel.swift` — the toggle action and
  viewport-preserving reassembly.
- **Modify** `SleepDaddy/Views/CompactSourceFilterButton.swift` — the toggle UI.
- **Modify** `SleepDaddy/Views/ContentView.swift:127-136` — wire the two new members.
- **Modify** `SleepDaddyTests/SleepPreferencesTests.swift`, `SleepDaddyTests/NightAssemblerTests.swift`,
  `SleepDaddyTests/NightBrowserModelTests.swift`, `SleepDaddyTests/SnapshotTests.swift`.

---

## Task 1: The awake spike smoother

**Files:**
- Create: `SleepDaddyTests/AwakeSpikeSmootherTests.swift`
- Create: `SleepDaddy/Services/AwakeSpikeSmoother.swift`

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/AwakeSpikeSmootherTests.swift` with exactly this content:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct AwakeSpikeSmootherTests {
    private let smoother = AwakeSpikeSmoother()
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func interval(
        _ id: String,
        _ stage: SleepStage,
        from: TimeInterval,
        to: TimeInterval,
        source: String = "com.apple.health"
    ) -> NormalizedSleepInterval {
        NormalizedSleepInterval(
            id: id,
            startDate: origin.addingTimeInterval(from),
            endDate: origin.addingTimeInterval(to),
            stage: stage,
            sourceName: source,
            sourceIdentifier: source
        )
    }

    @Test func testBriefAwakeBetweenMatchingStagesCollapsesToOneInterval() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("c2", .core, from: 660, to: 1200)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].startDate == origin)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(1200))
    }

    @Test func testAwakeJustOverThresholdIsKept() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 661),
            interval("c2", .core, from: 661, to: 1200)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testTwoMinuteAwakeIsKept() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 720),
            interval("c2", .core, from: 720, to: 1200)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testLaneWithoutBriefAwakesIsUnchanged() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("r1", .rem, from: 600, to: 1200)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testBriefAwakeBetweenDifferentStagesExtendsPredecessor() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("r1", .rem, from: 660, to: 1200)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 2)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(660))
        #expect(smoothed[1].stage == .rem)
        #expect(smoothed[1].startDate == origin.addingTimeInterval(660))
    }

    @Test func testBriefAwakeAtHeadIsAbsorbedByFollowingInterval() {
        let lane = [
            interval("a1", .awake, from: 0, to: 60),
            interval("c1", .core, from: 60, to: 600)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].startDate == origin)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(600))
    }

    @Test func testBriefAwakeAtTailIsAbsorbedByPrecedingInterval() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(660))
    }

    @Test func testMultipleBriefAwakesRemovedInOnePass() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("c2", .core, from: 660, to: 900),
            interval("a2", .awake, from: 900, to: 960),
            interval("c3", .core, from: 960, to: 1200)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].startDate == origin)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(1200))
    }

    @Test func testLaneOfOnlyBriefAwakesIsReturnedUnchanged() {
        let lane = [
            interval("a1", .awake, from: 0, to: 60),
            interval("a2", .awake, from: 120, to: 180)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testEmptyLaneIsReturnedUnchanged() {
        #expect(smoother.smooth(lane: []).isEmpty)
    }

    @Test func testSmoothedLaneCoversTheSameSpan() {
        let lane = [
            interval("a0", .awake, from: 0, to: 60),
            interval("c1", .core, from: 60, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("r1", .rem, from: 660, to: 1200),
            interval("a2", .awake, from: 1200, to: 1260)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.first?.startDate == lane.first?.startDate)
        #expect(smoothed.last?.endDate == lane.last?.endDate)
    }

    @Test func testSameStageFromDifferentSourcesIsNotCoalesced() {
        let lane = [
            interval("c1", .core, from: 0, to: 600, source: "com.apple.health"),
            interval("a1", .awake, from: 600, to: 660, source: "com.apple.health"),
            interval("c2", .core, from: 660, to: 1200, source: "com.oura.ring")
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 2)
        #expect(smoothed[0].sourceIdentifier == "com.apple.health")
        #expect(smoothed[0].endDate == origin.addingTimeInterval(660))
        #expect(smoothed[1].sourceIdentifier == "com.oura.ring")
        #expect(smoothed[1].startDate == origin.addingTimeInterval(660))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/AwakeSpikeSmootherTests
```

Expected: build failure, `cannot find 'AwakeSpikeSmoother' in scope`.

- [ ] **Step 3: Write the implementation**

Create `SleepDaddy/Services/AwakeSpikeSmoother.swift` with exactly this content:

```swift
import Foundation

/// Removes very short awake intervals from a lane without changing the span the lane covers.
///
/// This exists for drawing only. Night summaries are computed from the unsmoothed lane, so
/// hiding a spike here never changes a reported total.
public struct AwakeSpikeSmoother: Sendable {
    /// An awake interval of this duration or shorter is treated as a spike and hidden.
    public static let briefAwakeThreshold: TimeInterval = 60

    public init() {}

    /// - Parameter lane: intervals sorted by `startDate`, as produced by `NightAssembler`.
    /// - Returns: the lane with brief awake intervals removed, their time given to the
    ///   neighbouring interval so the lane stays gap-free.
    public func smooth(lane: [NormalizedSleepInterval]) -> [NormalizedSleepInterval] {
        // Nothing to hide, or nothing left if we did: return the input untouched. The second
        // case is a night recorded as brief awakes and nothing else, where smoothing would
        // empty the timeline while the summary still reported awake time.
        guard lane.contains(where: isBriefAwake) else { return lane }
        guard lane.contains(where: { !isBriefAwake($0) }) else { return lane }

        var kept: [NormalizedSleepInterval] = []
        var pendingHeadStart: Date?

        for interval in lane {
            guard isBriefAwake(interval) else {
                var next = interval
                if let headStart = pendingHeadStart {
                    next = next.copy(startDate: min(headStart, next.startDate))
                    pendingHeadStart = nil
                }
                kept.append(next)
                continue
            }

            if let last = kept.last {
                kept[kept.count - 1] = last.copy(endDate: max(last.endDate, interval.endDate))
            } else {
                // A spike opening the lane has nothing behind it, so the first interval that
                // survives will reach back over it instead.
                pendingHeadStart = min(pendingHeadStart ?? interval.startDate, interval.startDate)
            }
        }

        return coalesced(kept)
    }

    private func isBriefAwake(_ interval: NormalizedSleepInterval) -> Bool {
        interval.stage == .awake && interval.duration <= Self.briefAwakeThreshold
    }

    /// Merges neighbours that now touch and agree on stage and source, matching the rule the
    /// assembler uses when it builds the primary lane.
    private func coalesced(_ intervals: [NormalizedSleepInterval]) -> [NormalizedSleepInterval] {
        var result: [NormalizedSleepInterval] = []

        for interval in intervals {
            if let last = result.last,
               last.stage == interval.stage,
               last.sourceIdentifier == interval.sourceIdentifier,
               abs(interval.startDate.timeIntervalSince(last.endDate)) < 0.001 {
                result[result.count - 1] = last.copy(endDate: max(last.endDate, interval.endDate))
            } else {
                result.append(interval)
            }
        }

        return result
    }
}

private extension NormalizedSleepInterval {
    /// `NormalizedSleepInterval` is immutable, so widening one means rebuilding it. The
    /// identity of the absorbing interval is kept so lane IDs stay resolvable.
    func copy(startDate: Date? = nil, endDate: Date? = nil) -> NormalizedSleepInterval {
        NormalizedSleepInterval(
            id: id,
            startDate: startDate ?? self.startDate,
            endDate: endDate ?? self.endDate,
            stage: stage,
            sourceName: sourceName,
            sourceIdentifier: sourceIdentifier,
            deviceModel: deviceModel,
            bundleIdentifier: bundleIdentifier
        )
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project so it sees the new files**

```bash
xcodegen generate
```

Expected: `Created project at .../SleepDaddy.xcodeproj`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/AwakeSpikeSmootherTests
```

Expected: `TEST SUCCEEDED`, 12 tests passing.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Services/AwakeSpikeSmoother.swift SleepDaddyTests/AwakeSpikeSmootherTests.swift
git commit -m "feat: add AwakeSpikeSmoother for hiding one-minute awake spikes"
```

---

## Task 2: The `hidesBriefAwakes` preference

**Files:**
- Modify: `SleepDaddyTests/SleepPreferencesTests.swift`
- Modify: `SleepDaddy/Models/SleepPreferences.swift`

- [ ] **Step 1: Write the failing tests**

In `SleepDaddyTests/SleepPreferencesTests.swift`, add this assertion to the end of
`testPreferencesDefaults`, after the `excludedSampleIDs` line:

```swift
        #expect(prefs.hidesBriefAwakes == false)
```

Then add these two tests inside `struct SleepPreferencesTests`, after
`testPreferencesPersistence`:

```swift
    @Test func testDecodingPreferencesSavedBeforeBriefAwakeFlagKeepsEverythingElse() throws {
        // Written by a build that predates `hidesBriefAwakes`. Decoding must not throw:
        // PreferencesStore turns a decode failure into `.default`, silently wiping the
        // user's window, sources, and exclusions.
        let legacyJSON = Data("""
        {
            "coreWindowStartHour": 20,
            "coreWindowEndHour": 6,
            "selectedSourceIdentifiers": ["com.apple.health"],
            "excludedSampleIDs": ["sample-1"]
        }
        """.utf8)

        let prefs = try JSONDecoder().decode(SleepPreferences.self, from: legacyJSON)

        #expect(prefs.coreWindowStartHour == 20)
        #expect(prefs.coreWindowEndHour == 6)
        #expect(prefs.selectedSourceIdentifiers == ["com.apple.health"])
        #expect(prefs.excludedSampleIDs == ["sample-1"])
        #expect(prefs.hidesBriefAwakes == false)
    }

    @Test func testBriefAwakeFlagRoundTripsThroughTheStore() {
        let testDefaults = UserDefaults(suiteName: "SleepPreferencesTestsBriefAwake")!
        testDefaults.removePersistentDomain(forName: "SleepPreferencesTestsBriefAwake")

        let store = PreferencesStore(userDefaults: testDefaults)
        var prefs = store.load()
        prefs.hidesBriefAwakes = true
        store.save(prefs)

        #expect(store.load().hidesBriefAwakes == true)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepPreferencesTests
```

Expected: build failure, `value of type 'SleepPreferences' has no member 'hidesBriefAwakes'`.

- [ ] **Step 3: Write the implementation**

Replace the entire contents of `SleepDaddy/Models/SleepPreferences.swift` with:

```swift
import Foundation

public struct SleepPreferences: Equatable, Codable, Sendable {
    /// Default core window start hour (7:00 PM / 19:00)
    public var coreWindowStartHour: Int
    /// Default core window end hour (7:00 AM / 07:00 next day)
    public var coreWindowEndHour: Int
    /// Ordered list of selected HealthKit source identifiers. If empty, all sources are active by default.
    public var selectedSourceIdentifiers: [String]
    /// Set of locally excluded HealthKit sample IDs
    public var excludedSampleIDs: Set<String>
    /// Hides awake intervals of one minute or less from the timeline drawing.
    /// Night summaries are computed from the unfiltered lane and are unaffected.
    public var hidesBriefAwakes: Bool

    public init(
        coreWindowStartHour: Int = 19,
        coreWindowEndHour: Int = 7,
        selectedSourceIdentifiers: [String] = [],
        excludedSampleIDs: Set<String> = [],
        hidesBriefAwakes: Bool = false
    ) {
        self.coreWindowStartHour = coreWindowStartHour
        self.coreWindowEndHour = coreWindowEndHour
        self.selectedSourceIdentifiers = selectedSourceIdentifiers
        self.excludedSampleIDs = excludedSampleIDs
        self.hidesBriefAwakes = hidesBriefAwakes
    }

    /// Decoding is written out rather than synthesized so that preferences saved before a
    /// property existed still load. Synthesized decoding treats a missing key as an error and
    /// ignores the default value, and `PreferencesStore.load()` turns any error into
    /// `.default` — which would discard the stored window, sources, and exclusions on upgrade.
    /// Any property added here in future must use `decodeIfPresent` for the same reason.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.coreWindowStartHour = try container.decode(Int.self, forKey: .coreWindowStartHour)
        self.coreWindowEndHour = try container.decode(Int.self, forKey: .coreWindowEndHour)
        self.selectedSourceIdentifiers = try container.decode([String].self, forKey: .selectedSourceIdentifiers)
        self.excludedSampleIDs = try container.decode(Set<String>.self, forKey: .excludedSampleIDs)
        self.hidesBriefAwakes = try container.decodeIfPresent(Bool.self, forKey: .hidesBriefAwakes) ?? false
    }

    public static let `default` = SleepPreferences()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SleepPreferencesTests
```

Expected: `TEST SUCCEEDED`, 4 tests passing.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Models/SleepPreferences.swift SleepDaddyTests/SleepPreferencesTests.swift
git commit -m "feat: add hidesBriefAwakes preference with migration-safe decoding"
```

---

## Task 3: The display lane on `AssembledNight`

**Files:**
- Modify: `SleepDaddyTests/NightAssemblerTests.swift`
- Modify: `SleepDaddy/Models/AssembledNight.swift:15`, `:40`, `:51`
- Modify: `SleepDaddy/Services/NightAssembler.swift:19-31`, `:60-72`, `:126-139`

- [ ] **Step 1: Write the failing tests**

Add these two tests inside `struct NightAssemblerTests` in
`SleepDaddyTests/NightAssemblerTests.swift`, at the end of the struct:

```swift
    /// Core, a one-minute awake, then core again — all inside the default core window.
    private func laneWithBriefAwake() -> [NormalizedSleepInterval] {
        let startOfDay = calendar.startOfDay(for: sampleDate)
        let p10PM = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: startOfDay)!

        return [
            NormalizedSleepInterval(
                id: "c1",
                startDate: p10PM,
                endDate: p10PM.addingTimeInterval(3600),
                stage: .core,
                sourceName: "Watch",
                sourceIdentifier: "com.apple.watch"
            ),
            NormalizedSleepInterval(
                id: "a1",
                startDate: p10PM.addingTimeInterval(3600),
                endDate: p10PM.addingTimeInterval(3660),
                stage: .awake,
                sourceName: "Watch",
                sourceIdentifier: "com.apple.watch"
            ),
            NormalizedSleepInterval(
                id: "c2",
                startDate: p10PM.addingTimeInterval(3660),
                endDate: p10PM.addingTimeInterval(10800),
                stage: .core,
                sourceName: "Watch",
                sourceIdentifier: "com.apple.watch"
            )
        ]
    }

    @Test func testDisplayLaneMatchesPrimaryLaneWhenFilterIsOff() {
        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: laneWithBriefAwake(),
            preferences: .default
        )

        #expect(assembled.displayLaneIntervals == assembled.primaryLaneIntervals)
    }

    @Test func testBriefAwakeFilterChangesOnlyTheDisplayLane() {
        var hidingPrefs = SleepPreferences.default
        hidingPrefs.hidesBriefAwakes = true

        let intervals = laneWithBriefAwake()
        let shown = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: intervals,
            preferences: .default
        )
        let hidden = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: intervals,
            preferences: hidingPrefs
        )

        // Everything that is reported to the user is untouched.
        #expect(hidden.summary == shown.summary)
        #expect(hidden.summary.awakeDuration == 60)
        #expect(hidden.detectedStart == shown.detectedStart)
        #expect(hidden.detectedEnd == shown.detectedEnd)
        #expect(hidden.rawIntervals == shown.rawIntervals)
        #expect(hidden.primaryLaneIntervals == shown.primaryLaneIntervals)

        // Only the drawn lane loses the spike.
        #expect(hidden.displayLaneIntervals.count < hidden.primaryLaneIntervals.count)
        #expect(!hidden.displayLaneIntervals.contains { $0.stage == .awake })
        #expect(hidden.displayLaneIntervals.first?.startDate == shown.primaryLaneIntervals.first?.startDate)
        #expect(hidden.displayLaneIntervals.last?.endDate == shown.primaryLaneIntervals.last?.endDate)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightAssemblerTests
```

Expected: build failure, `value of type 'AssembledNight' has no member 'displayLaneIntervals'`.

- [ ] **Step 3: Add the property to `AssembledNight`**

In `SleepDaddy/Models/AssembledNight.swift`, add this line immediately after
`public let primaryLaneIntervals: [NormalizedSleepInterval]` (line 15):

```swift
    /// The lane the timeline draws. Equal to `primaryLaneIntervals` unless a display filter
    /// such as `SleepPreferences.hidesBriefAwakes` is active. Never used for summaries.
    public let displayLaneIntervals: [NormalizedSleepInterval]
```

Add this parameter to `init`, immediately after the `primaryLaneIntervals:` parameter (line 40):

```swift
        displayLaneIntervals: [NormalizedSleepInterval],
```

And this assignment immediately after `self.primaryLaneIntervals = primaryLaneIntervals` (line 51):

```swift
        self.displayLaneIntervals = displayLaneIntervals
```

- [ ] **Step 4: Populate it in `NightAssembler`**

In `SleepDaddy/Services/NightAssembler.swift`, add this stored property immediately after
`public init() {}` (line 4):

```swift
    private let awakeSpikeSmoother = AwakeSpikeSmoother()
```

In **both** early-return `AssembledNight(...)` literals — the one at line 19 and the one at
line 60 — add this line immediately after the `primaryLaneIntervals: [],` line:

```swift
                displayLaneIntervals: [],
```

Then, in `assembleNight`, immediately after the summary is calculated (the
`let summary = calculateSummary(...)` call at line 126) insert:

```swift
        // Runs after the summary so a hidden spike can never reach a reported total.
        let displayLane = preferences.hidesBriefAwakes
            ? awakeSpikeSmoother.smooth(lane: primaryLane)
            : primaryLane
```

And in the final `AssembledNight(...)` literal, add this line immediately after
`primaryLaneIntervals: primaryLane,`:

```swift
            displayLaneIntervals: displayLane,
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightAssemblerTests
```

Expected: `TEST SUCCEEDED`, with the two new tests passing alongside the existing ones.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Models/AssembledNight.swift SleepDaddy/Services/NightAssembler.swift SleepDaddyTests/NightAssemblerTests.swift
git commit -m "feat: assemble a display lane with brief awakes optionally hidden"
```

---

## Task 4: Draw, tap, and describe from the display lane

**Files:**
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:167`, `:174`, `:198`, `:326`, `:334`

There are exactly five reads of `night.primaryLaneIntervals` in this file and all five change.
Drawing, hit-testing, and VoiceOver must agree, or a hidden spike stays tappable and audible
while being invisible.

- [ ] **Step 1: Replace all five reads**

```bash
sed -i '' 's/night\.primaryLaneIntervals/night.displayLaneIntervals/g' SleepDaddy/Views/SleepTimelineCanvas.swift
```

- [ ] **Step 2: Verify exactly five replacements landed and none were missed**

```bash
grep -c "night.displayLaneIntervals" SleepDaddy/Views/SleepTimelineCanvas.swift
grep -c "night.primaryLaneIntervals" SleepDaddy/Views/SleepTimelineCanvas.swift
```

Expected: `5` from the first command, `0` from the second.

- [ ] **Step 3: Run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `TEST SUCCEEDED`. The existing snapshot references must still match — with the
preference off the display lane is identical to the primary lane, so the rendering is
unchanged. A snapshot failure here is a real regression; investigate rather than regenerating
the PNG.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Views/SleepTimelineCanvas.swift
git commit -m "refactor: render and hit-test the timeline from the display lane"
```

---

## Task 5: The toggle action on `NightBrowserModel`

**Files:**
- Modify: `SleepDaddyTests/NightBrowserModelTests.swift`
- Modify: `SleepDaddy/ViewModels/NightBrowserModel.swift:114-133`

- [ ] **Step 1: Write the failing test**

Add this test inside `struct NightBrowserModelTests` in
`SleepDaddyTests/NightBrowserModelTests.swift`, after `testExcludingAndRestoringRecord`:

```swift
    @Test @MainActor func testTogglingBriefAwakeFilterKeepsTheViewport() async {
        let fixtureStore = FixtureSleepStore()
        let testDefaults = UserDefaults(suiteName: "NightBrowserModelTestsBriefAwake")!
        testDefaults.removePersistentDomain(forName: "NightBrowserModelTestsBriefAwake")
        let prefsStore = PreferencesStore(userDefaults: testDefaults)

        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore)
        await model.loadData()

        // Zoom in an hour on each side, then remember where we ended up.
        model.updateViewport(
            start: model.viewportStart.addingTimeInterval(3600),
            end: model.viewportEnd.addingTimeInterval(-3600)
        )
        let expectedStart = model.viewportStart
        let expectedEnd = model.viewportEnd
        model.selectedInterval = model.selectedAssembledNight?.primaryLaneIntervals.first

        model.toggleHideBriefAwakes()

        #expect(model.preferences.hidesBriefAwakes == true)
        #expect(model.viewportStart == expectedStart)
        #expect(model.viewportEnd == expectedEnd)
        // A selection made before the toggle may name an interval the display lane no longer has.
        #expect(model.selectedInterval == nil)

        model.toggleHideBriefAwakes()

        #expect(model.preferences.hidesBriefAwakes == false)
        #expect(model.viewportStart == expectedStart)
        #expect(model.viewportEnd == expectedEnd)
    }

    @Test @MainActor func testTogglingBriefAwakeFilterPersists() async {
        let fixtureStore = FixtureSleepStore()
        let testDefaults = UserDefaults(suiteName: "NightBrowserModelTestsBriefAwakePersist")!
        testDefaults.removePersistentDomain(forName: "NightBrowserModelTestsBriefAwakePersist")
        let prefsStore = PreferencesStore(userDefaults: testDefaults)

        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore)
        await model.loadData()
        model.toggleHideBriefAwakes()

        #expect(prefsStore.load().hidesBriefAwakes == true)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightBrowserModelTests
```

Expected: build failure, `value of type 'NightBrowserModel' has no member 'toggleHideBriefAwakes'`.

- [ ] **Step 3: Write the implementation**

In `SleepDaddy/ViewModels/NightBrowserModel.swift`, change the signature of
`reassembleNights` (line 114) from:

```swift
    public func reassembleNights() {
```

to:

```swift
    /// - Parameter preservingViewport: pass `true` only when the change cannot move a night's
    ///   bounds — a display-only preference. Source selection, exclusions, and the core window
    ///   all shift `detectedStart` / `detectedEnd`, so those must re-derive the viewport.
    public func reassembleNights(preservingViewport: Bool = false) {
```

and change the final line of its body (line 132) from:

```swift
        resetViewportToSelectedNight()
```

to:

```swift
        if !preservingViewport {
            resetViewportToSelectedNight()
        }
```

Then add this method immediately after `clearSourceSelection()` (line 164):

```swift
    public func toggleHideBriefAwakes() {
        preferences.hidesBriefAwakes.toggle()
        preferencesStore.save(preferences)
        // The selection may name an interval that is no longer in the display lane, which
        // would leave the inspector open over a segment the canvas can no longer emphasise.
        selectedInterval = nil
        reassembleNights(preservingViewport: true)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightBrowserModelTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/ViewModels/NightBrowserModel.swift SleepDaddyTests/NightBrowserModelTests.swift
git commit -m "feat: add brief awake toggle that preserves the timeline viewport"
```

---

## Task 6: The toggle in the filter sheet

**Files:**
- Modify: `SleepDaddy/Views/CompactSourceFilterButton.swift`
- Modify: `SleepDaddy/Views/ContentView.swift:127-136`

This task is UI wiring with no logic of its own; it is verified by the build, the existing
`compact_source_filter_button_snapshot` reference, and Task 7's snapshot.

- [ ] **Step 1: Add the two new members to `CompactSourceFilterButton`**

In `SleepDaddy/Views/CompactSourceFilterButton.swift`, add these two stored properties
immediately after `let selectedSourceIDs: [String]` (line 5):

```swift
    let hidesBriefAwakes: Bool
    let onToggleHideBriefAwakes: () -> Void
```

Change the `init` to:

```swift
    public init(
        availableSources: [String: String],
        selectedSourceIDs: [String],
        hidesBriefAwakes: Bool,
        onToggleSource: @escaping (String) -> Void,
        onClearFilter: @escaping () -> Void,
        onToggleHideBriefAwakes: @escaping () -> Void
    ) {
        self.availableSources = availableSources
        self.selectedSourceIDs = selectedSourceIDs
        self.hidesBriefAwakes = hidesBriefAwakes
        self.onToggleSource = onToggleSource
        self.onClearFilter = onClearFilter
        self.onToggleHideBriefAwakes = onToggleHideBriefAwakes
    }
```

- [ ] **Step 2: Widen the active-filter dot condition**

A timeline that is hiding data must say so. Change line 32 from:

```swift
                if !selectedSourceIDs.isEmpty {
```

to:

```swift
                if !selectedSourceIDs.isEmpty || hidesBriefAwakes {
```

- [ ] **Step 3: Add the Timeline Display section**

Insert this section between the intro-text `Section` (which closes at line 50) and
`Section("Sources")`:

```swift
                    Section(
                        header: Text("Timeline Display"),
                        footer: Text("Awake periods of one minute or less are hidden from the timeline. Sleep totals are unaffected.")
                    ) {
                        Toggle("Hide Brief Awakes", isOn: Binding(
                            get: { hidesBriefAwakes },
                            set: { _ in onToggleHideBriefAwakes() }
                        ))
                        .accessibilityHint("Hides awake periods of one minute or less from the timeline drawing")
                    }
```

- [ ] **Step 4: Wire it up in `ContentView`**

Replace the `CompactSourceFilterButton(...)` call at `SleepDaddy/Views/ContentView.swift:127-136`
with:

```swift
                        CompactSourceFilterButton(
                            availableSources: model.availableSources,
                            selectedSourceIDs: model.preferences.selectedSourceIdentifiers,
                            hidesBriefAwakes: model.preferences.hidesBriefAwakes,
                            onToggleSource: { sourceID in
                                model.toggleSourceSelection(sourceID)
                            },
                            onClearFilter: {
                                model.clearSourceSelection()
                            },
                            onToggleHideBriefAwakes: {
                                model.toggleHideBriefAwakes()
                            }
                        )
```

- [ ] **Step 5: Update the other call site**

`SnapshotTests.swift:348` also constructs this view and will not compile without the new
arguments. Replace the `CompactSourceFilterButton(...)` call at
`SleepDaddyTests/SnapshotTests.swift:348-353` with:

```swift
        let filterButton = CompactSourceFilterButton(
            availableSources: ["com.apple.health": "Apple Watch", "com.oura.ring": "Oura Ring"],
            selectedSourceIDs: ["com.apple.health"],
            hidesBriefAwakes: false,
            onToggleSource: { _ in },
            onClearFilter: {},
            onToggleHideBriefAwakes: {}
        )
```

The `compact_source_filter_button_snapshot` reference must still match: the test already
selects a source, so the active-filter dot was drawn before this change and is drawn now.

- [ ] **Step 6: Build and run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add SleepDaddy/Views/CompactSourceFilterButton.swift SleepDaddy/Views/ContentView.swift SleepDaddyTests/SnapshotTests.swift
git commit -m "feat: add Hide Brief Awakes toggle to the filter sheet"
```

---

## Task 7: Snapshot of a spike-heavy night

**Files:**
- Modify: `SleepDaddyTests/SnapshotTests.swift`
- Create: `SleepDaddyTests/ReferenceSnapshots/snapshot_brief_awakes_hidden.png` (generated)

- [ ] **Step 1: Write the test**

Add this test inside `struct SnapshotTests` in `SleepDaddyTests/SnapshotTests.swift`, after
`testSleepTimelineCanvasSnapshotComposition`. It calls the existing private `compareImages`
helper in the same struct.

```swift
    @Test @MainActor func testCanvasSnapshotWithBriefAwakesHidden() throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        func watch(_ id: String, _ stage: SleepStage, _ from: TimeInterval, _ to: TimeInterval) -> NormalizedSleepInterval {
            NormalizedSleepInterval(
                id: id,
                startDate: coreStart.addingTimeInterval(from),
                endDate: coreStart.addingTimeInterval(to),
                stage: stage,
                sourceName: "Apple Watch",
                sourceIdentifier: "com.apple.health"
            )
        }

        // A night peppered with one-minute awake spikes, the pattern this filter exists for.
        let fixtureIntervals = [
            watch("core1", .core, 3600, 7200),
            watch("spike1", .awake, 7200, 7260),
            watch("core2", .core, 7260, 9000),
            watch("spike2", .awake, 9000, 9060),
            watch("deep1", .deep, 9060, 12600),
            watch("spike3", .awake, 12600, 12660),
            watch("rem1", .rem, 12660, 16200),
            watch("awake1", .awake, 16200, 18000),
            watch("core3", .core, 18000, 21600)
        ]

        var hidingPrefs = SleepPreferences.default
        hidingPrefs.hidesBriefAwakes = true

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: hidingPrefs
        )

        // The three spikes go; the 30-minute awake stays.
        #expect(night.displayLaneIntervals.filter { $0.stage == .awake }.count == 1)

        let canvas = SleepTimelineCanvas(
            night: night,
            viewportStart: night.detectedStart,
            viewportEnd: night.detectedEnd,
            selectedIntervalID: nil,
            onSelectInterval: { _ in },
            onUpdateViewport: { _, _ in }
        )
        .frame(width: 393, height: 320)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.timelineInteractionEnabled, false)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0
        guard let currentImage = renderer.uiImage,
              let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render brief awake snapshot PNG")
            return
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("snapshot_brief_awakes_hidden.png")

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG")
                return
            }

            #expect(cgCurrent.width == cgReference.width, "Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")

            let imagesMatch = compareImages(cgCurrent: cgCurrent, cgReference: cgReference)
            #expect(imagesMatch, "Rendered snapshot image pixels do not match reference PNG snapshot")
        }
    }
```

- [ ] **Step 2: Run it once to write the baseline**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Expected: `TEST SUCCEEDED`. The new reference PNG is written on this run.

- [ ] **Step 3: Run it again to verify it compares**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Expected: `TEST SUCCEEDED`, this time comparing against the file written in Step 2.

- [ ] **Step 4: Inspect the reference image by eye**

Open `SleepDaddyTests/ReferenceSnapshots/snapshot_brief_awakes_hidden.png` and confirm the
stepped path runs unbroken through where the three spikes were, with no one-minute gaps in the
line, and that the single 30-minute awake is still drawn on the Awake row.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `TEST SUCCEEDED`, all suites.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddyTests/SnapshotTests.swift SleepDaddyTests/ReferenceSnapshots/snapshot_brief_awakes_hidden.png
git commit -m "test: snapshot a spike-heavy night with brief awakes hidden"
```

---

## Task 8: Document the feature

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the feature to the Key Features list**

In `README.md`, add this bullet immediately after the **Explicit Source Filtering** bullet:

```markdown
- **Brief Awake Filtering**: Optionally hide awake intervals of one minute or less from the timeline, for trackers that emit many short awake samples. Drawing only — sleep, awake, and stage totals are always reported from the unfiltered data.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document the brief awake filter"
```
