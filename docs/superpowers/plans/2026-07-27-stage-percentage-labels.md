# Stage Percentage Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each sleep stage's whole-number share of the night beneath its row label in the timeline chart.

**Architecture:** A pure `NightSummary` extension computes `[SleepStage: Int]` percentages using the largest-remainder method so the four displayed values always sum to exactly 100. `SleepTimelineCanvas` reads it from the `AssembledNight` it already holds and renders a second line under each stage row label. No view model or initializer changes; `ShareTimelineCardView` inherits the change because it renders the same canvas.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-27-stage-percentage-labels-design.md`

---

## Background for the implementer

`NightSummary` (`SleepDaddy/Models/NightSummary.swift`) already carries
`stageDurations: [SleepStage: TimeInterval]`, populated by `NightAssembler.calculateSummary`.
Nothing displays it today.

`SleepStage` (`SleepDaddy/Models/SleepStage.swift`) is an enum with cases `awake`, `rem`,
`core`, `deep`, `asleepUnspecified`, `inBed`. It has `displayName` (e.g. `"Deep"`) and
`rowIndex` (`awake` 0, `rem` 1, `core` 2, `deep` 3, `asleepUnspecified` 4, `inBed` 5).

`SleepTimelineGeometry.defaultDisplayedStages` is `[.awake, .rem, .core, .deep]` — the four
stages that own a labelled row in the chart. Those are exactly the four that get percentages.

**Important build note:** `project.yml` globs sources by directory (`path: SleepDaddy`), so a
newly created `.swift` file is invisible to Xcode until `xcodegen generate` runs. Task 1
includes that step. Do not commit `SleepDaddy.xcodeproj` or `Info.plist` — they are generated.

**Snapshot tests** compare rendered PNGs against references in
`SleepDaddyTests/ReferenceSnapshots/`. When a reference file is missing, the test writes it
and passes. Regenerating a reference therefore means: delete the PNG, run the suite (writes
the new baseline), run the suite again (verifies it matches). Task 3 does this.

---

## File Structure

- **Create** `SleepDaddy/Models/NightSummary+StagePercentages.swift` — the percentage
  calculation. Kept out of `NightSummary.swift` so the model stays a plain data container and
  the algorithm is separately testable.
- **Create** `SleepDaddyTests/NightSummaryStagePercentagesTests.swift` — unit tests for that
  calculation.
- **Modify** `SleepDaddy/Views/SleepTimelineCanvas.swift:73-88` — the fixed leading label
  column.
- **Regenerate** seven PNGs in `SleepDaddyTests/ReferenceSnapshots/`.

---

## Task 1: Stage percentage calculation

**Files:**
- Create: `SleepDaddyTests/NightSummaryStagePercentagesTests.swift`
- Create: `SleepDaddy/Models/NightSummary+StagePercentages.swift`

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/NightSummaryStagePercentagesTests.swift` with exactly this content:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct NightSummaryStagePercentagesTests {
    /// Builds a summary carrying only the stage durations under test.
    /// The other fields do not affect `stagePercentages`.
    private func makeSummary(
        awake: TimeInterval = 0,
        rem: TimeInterval = 0,
        core: TimeInterval = 0,
        deep: TimeInterval = 0,
        unspecified: TimeInterval = 0,
        inBed: TimeInterval = 0
    ) -> NightSummary {
        NightSummary(
            totalSleepDuration: rem + core + deep + unspecified,
            awakeDuration: awake,
            inBedDuration: inBed,
            stageDurations: [
                .awake: awake,
                .rem: rem,
                .core: core,
                .deep: deep,
                .asleepUnspecified: unspecified,
                .inBed: inBed
            ],
            conflictCount: 0
        )
    }

    private let minute: TimeInterval = 60

    @Test func percentagesSumToOneHundredForATypicalNight() {
        let summary = makeSummary(
            awake: 18 * minute,
            rem: 99 * minute,
            core: 231 * minute,
            deep: 104 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 4)
        #expect(percentages[.rem] == 22)
        #expect(percentages[.core] == 51)
        #expect(percentages[.deep] == 23)
        #expect(percentages.values.reduce(0, +) == 100)
    }

    @Test func equalDurationsSplitEvenly() {
        let summary = makeSummary(
            awake: 60 * minute,
            rem: 60 * minute,
            core: 60 * minute,
            deep: 60 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 25)
        #expect(percentages[.rem] == 25)
        #expect(percentages[.core] == 25)
        #expect(percentages[.deep] == 25)
    }

    /// Independent rounding of 17.5/27.5/27.5/27.5 would total 102.
    /// Largest remainder must keep the column at 100, and the three-way tie
    /// among the .5 remainders must be resolved by row order.
    @Test func largestRemainderPreventsOvershootAndBreaksTiesByRowOrder() {
        let summary = makeSummary(
            awake: 17.5 * minute,
            rem: 27.5 * minute,
            core: 27.5 * minute,
            deep: 27.5 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 18)
        #expect(percentages[.rem] == 28)
        #expect(percentages[.core] == 27)
        #expect(percentages[.deep] == 27)
        #expect(percentages.values.reduce(0, +) == 100)
    }

    @Test func unspecifiedAndInBedAreExcludedFromTheDenominator() {
        let summary = makeSummary(
            core: 30 * minute,
            deep: 30 * minute,
            unspecified: 60 * minute,
            inBed: 480 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.core] == 50)
        #expect(percentages[.deep] == 50)
        #expect(percentages[.awake] == 0)
        #expect(percentages[.rem] == 0)
        #expect(percentages[.asleepUnspecified] == nil)
        #expect(percentages[.inBed] == nil)
        #expect(percentages.values.reduce(0, +) == 100)
    }

    @Test func aNightOfOnlyUnspecifiedSleepHasNoPercentages() {
        let summary = makeSummary(unspecified: 440 * minute, inBed: 480 * minute)

        #expect(summary.stagePercentages.isEmpty)
    }

    @Test func anEmptySummaryHasNoPercentages() {
        #expect(NightSummary.empty.stagePercentages.isEmpty)
    }

    @Test func missingStageKeysCountAsZero() {
        let summary = NightSummary(
            totalSleepDuration: 120 * minute,
            awakeDuration: 0,
            inBedDuration: 0,
            stageDurations: [.core: 90 * minute, .deep: 30 * minute],
            conflictCount: 0
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 0)
        #expect(percentages[.rem] == 0)
        #expect(percentages[.core] == 75)
        #expect(percentages[.deep] == 25)
    }
}
```

- [ ] **Step 2: Regenerate the project so the new test file is compiled**

Run:

```bash
xcodegen generate
```

Expected: `Generated project at /Users/kevm/github/sleepdaddy/SleepDaddy.xcodeproj`

- [ ] **Step 3: Run the tests to verify they fail**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightSummaryStagePercentagesTests 2>&1 | tail -30
```

Expected: compilation failure — `value of type 'NightSummary' has no member 'stagePercentages'`.

- [ ] **Step 4: Write the implementation**

Create `SleepDaddy/Models/NightSummary+StagePercentages.swift` with exactly this content:

```swift
import Foundation

extension NightSummary {
    /// The stages that own a labelled row in the timeline chart, in row order.
    static let percentageStages: [SleepStage] = [.awake, .rem, .core, .deep]

    /// Each labelled stage's whole-number share of the night.
    ///
    /// The denominator is the sum of `percentageStages` only. `asleepUnspecified` and
    /// `inBed` are excluded because neither owns a row that could carry a label, and
    /// including them would leave the visible column summing to less than 100 with no
    /// indication of where the remainder went.
    ///
    /// Values are distributed by the largest-remainder method so they sum to exactly 100.
    /// Rounding each value independently would land the column on 99 or 101 for many
    /// nights. Ties are broken by `SleepStage.rowIndex`, making the result deterministic.
    ///
    /// The arithmetic is done on whole seconds as integers rather than on percentages as
    /// `Double`s. In floating point a true 27.5% evaluates to 27.500000000000004, which
    /// makes an exact tie between remainders unrepresentable and lets rounding noise decide
    /// which stage receives a leftover point. Integer division and modulo make both the
    /// remainder comparison and the tie-break exact.
    ///
    /// Returns an empty dictionary when no labelled stage has any duration, which is the
    /// case for a night recorded entirely as unspecified sleep. Callers show no
    /// percentages at all rather than four rows reading `0%`.
    public var stagePercentages: [SleepStage: Int] {
        let seconds = Self.percentageStages.map { stage in
            max(0, Int((stageDurations[stage] ?? 0).rounded()))
        }
        let total = seconds.reduce(0, +)
        guard total > 0 else { return [:] }

        let scaled = seconds.map { $0 * 100 }
        var whole = scaled.map { $0 / total }
        let remainders = scaled.map { $0 % total }

        let leftover = 100 - whole.reduce(0, +)
        if leftover > 0 {
            let byDescendingRemainder = remainders.indices.sorted { lhs, rhs in
                if remainders[lhs] == remainders[rhs] {
                    return Self.percentageStages[lhs].rowIndex
                        < Self.percentageStages[rhs].rowIndex
                }
                return remainders[lhs] > remainders[rhs]
            }
            for index in byDescendingRemainder.prefix(leftover) {
                whole[index] += 1
            }
        }

        return Dictionary(uniqueKeysWithValues: zip(Self.percentageStages, whole))
    }
}
```

Worked example for the tie test in Step 1: seconds are `[1050, 1650, 1650, 1650]`, total
`6000`. Scaled: `[105000, 165000, 165000, 165000]`. Integer division gives
`[17, 27, 27, 27]`, summing to 98, so `leftover` is 2. Every remainder is exactly `3000`, so
the tie-break by `rowIndex` hands the two points to `awake` and `rem`, giving
`[18, 28, 27, 27]`.

- [ ] **Step 5: Regenerate the project so the new source file is compiled**

Run:

```bash
xcodegen generate
```

Expected: `Generated project at /Users/kevm/github/sleepdaddy/SleepDaddy.xcodeproj`

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightSummaryStagePercentagesTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`, with all 7 tests passing.

- [ ] **Step 7: Commit**

```bash
git add SleepDaddy/Models/NightSummary+StagePercentages.swift SleepDaddyTests/NightSummaryStagePercentagesTests.swift
git commit -m "feat: compute whole-number stage percentages"
```

---

## Task 2: Render percentages in the chart label column

**Files:**
- Modify: `SleepDaddy/Views/SleepTimelineCanvas.swift:73-88`

- [ ] **Step 1: Read the current label column**

Open `SleepDaddy/Views/SleepTimelineCanvas.swift`. Inside the `GeometryReader`, line 73 reads:

```swift
            let displayedStages = SleepTimelineGeometry.defaultDisplayedStages
```

and lines 76-88 are the fixed leading label column:

```swift
                // Fixed leading stage labels outside moving plot region
                ZStack(alignment: .topLeading) {
                    ForEach(displayedStages, id: \.self) { stage in
                        let yCenter = geom.yCenterPosition(for: stage, displayedStages: displayedStages)
                        Text(stage.displayName)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(stage.themeColor)
                            .frame(width: labelWidth, alignment: .leading)
                            .position(x: labelWidth / 2.0, y: yCenter)
                    }
                }
                .frame(width: labelWidth, height: totalHeight, alignment: .topLeading)
```

- [ ] **Step 2: Add the percentages lookup**

Replace line 73:

```swift
            let displayedStages = SleepTimelineGeometry.defaultDisplayedStages
```

with:

```swift
            let displayedStages = SleepTimelineGeometry.defaultDisplayedStages
            let stagePercentages = night.summary.stagePercentages
```

- [ ] **Step 3: Replace the label column**

Replace the whole block shown in Step 1 (the comment line through the trailing `.frame(...)`)
with:

```swift
                // Fixed leading stage labels outside moving plot region
                ZStack(alignment: .topLeading) {
                    ForEach(displayedStages, id: \.self) { stage in
                        let yCenter = geom.yCenterPosition(for: stage, displayedStages: displayedStages)
                        let percentage = stagePercentages[stage]
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.displayName)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(stage.themeColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if let percentage {
                                Text("\(percentage)%")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .frame(width: labelWidth, alignment: .leading)
                        .position(x: labelWidth / 2.0, y: yCenter)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            percentage.map { "\(stage.displayName), \($0) percent of night" }
                                ?? stage.displayName
                        )
                    }
                }
                .frame(width: labelWidth, height: totalHeight, alignment: .topLeading)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
```

Notes on why each piece is there:

- The `.position(x:y:)` call is unchanged, so the two-line block stays vertically centred on
  its row and the plot geometry is untouched.
- `.monospacedDigit()` stops the numbers changing width between nights.
- `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` caps the label column only. Row height
  is roughly 49pt on the detail screen; two unclamped `.caption2` lines overflow into the
  neighbouring row at accessibility sizes.
- When `stagePercentages` is empty, `percentage` is `nil` for every stage and the column
  renders exactly as it did before this change.

- [ ] **Step 4: Build to verify it compiles**

Run:

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run the non-snapshot suites to verify nothing regressed**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -skip-testing:SleepDaddyTests/SnapshotTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. Snapshot tests are skipped here because their references
are now stale by design; Task 3 regenerates them.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Views/SleepTimelineCanvas.swift
git commit -m "feat: label chart rows with stage percentages"
```

---

## Task 3: Regenerate snapshot references

**Files:**
- Modify: `SleepDaddyTests/ReferenceSnapshots/timeline_canvas_snapshot.png`
- Modify: `SleepDaddyTests/ReferenceSnapshots/share_card_snapshot.png`
- Modify: `SleepDaddyTests/ReferenceSnapshots/snapshot_portrait_light.png`
- Modify: `SleepDaddyTests/ReferenceSnapshots/snapshot_portrait_dark.png`
- Modify: `SleepDaddyTests/ReferenceSnapshots/snapshot_landscape.png`
- Modify: `SleepDaddyTests/ReferenceSnapshots/snapshot_dynamic_type.png`
- Modify: `SleepDaddyTests/ReferenceSnapshots/snapshot_reduce_motion.png`

The other references in that directory are unaffected and must not be deleted:
`compact_source_filter_button_snapshot.png` (no chart),
`sleep-timeline-redesign-reference.png` (night header only), and
`snapshot_empty_loaded_night.png` (empty night renders the placeholder, not the canvas).

- [ ] **Step 1: Confirm the snapshot tests fail against the current references**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests 2>&1 | tail -40
```

Expected: `** TEST FAILED **` with pixel-mismatch messages such as
`Rendered snapshot image pixels do not match reference PNG snapshot`. This is the proof that
the labels actually changed what is drawn.

- [ ] **Step 2: Delete the seven stale references**

Run:

```bash
cd /Users/kevm/github/sleepdaddy && rm SleepDaddyTests/ReferenceSnapshots/timeline_canvas_snapshot.png SleepDaddyTests/ReferenceSnapshots/share_card_snapshot.png SleepDaddyTests/ReferenceSnapshots/snapshot_portrait_light.png SleepDaddyTests/ReferenceSnapshots/snapshot_portrait_dark.png SleepDaddyTests/ReferenceSnapshots/snapshot_landscape.png SleepDaddyTests/ReferenceSnapshots/snapshot_dynamic_type.png SleepDaddyTests/ReferenceSnapshots/snapshot_reduce_motion.png
```

- [ ] **Step 3: Run the snapshot tests to write new baselines**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` — each test found no reference file and wrote one.

- [ ] **Step 4: Inspect the new baselines before trusting them**

Run:

```bash
open SleepDaddyTests/ReferenceSnapshots/snapshot_portrait_light.png SleepDaddyTests/ReferenceSnapshots/snapshot_dynamic_type.png
```

Check by eye:

- Each of the four stage labels has a percentage beneath it.
- The four percentages add up to 100.
- In the dynamic-type image, no percentage line collides with the label of the row below it.

If the dynamic-type image shows a collision, the `.dynamicTypeSize` cap in Task 2 Step 3 is
not taking effect — fix that before continuing rather than committing a bad baseline.

- [ ] **Step 5: Re-run the full suite to verify the new baselines match**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` for every suite, snapshots included.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddyTests/ReferenceSnapshots
git commit -m "test: regenerate snapshots for stage percentage labels"
```
