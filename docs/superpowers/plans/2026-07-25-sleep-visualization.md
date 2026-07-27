# SleepDaddy Sleep Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only iOS app that browses HealthKit sleep by night, filters and excludes sources, detects contiguous sleep outside a 7:00 PM–7:00 AM core window, provides a zoomable custom timeline, and shares the current viewport as an image.

**Architecture:** HealthKit is isolated behind an async store that returns application-owned values. Pure normalizer and night-assembly types handle stage mapping, filtering, exclusions, adaptive boundaries, summaries, and conflict resolution. A main-actor browser model feeds SwiftUI screens, a custom `Canvas` timeline, and a dedicated `ImageRenderer` share view.

**Tech Stack:** Swift 6, SwiftUI, HealthKit, Observation, Swift Testing, XcodeGen, iOS 26.

## Global Constraints

- The app is read-only and never saves, edits, or deletes HealthKit data.
- The minimum deployment target is iOS 26.0.
- Use Swift 6 with strict concurrency-compatible application-owned data types.
- Use XcodeGen; do not edit or commit `SleepDaddy.xcodeproj`.
- Generate `Sources/Info.plist` from `project.yml`; do not commit it.
- Use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, and `#require`) rather than XCTest assertions.
- Use the iPhone 17 simulator for local builds and automated tests.
- Use the bundle identifier prefix `fm.rodeo`.
- Add no third-party runtime or analytics dependencies.
- Persist only settings, selected source identifiers, and excluded sample identifiers.
- Treat 7:00 PM–7:00 AM as the default core window, with a 30-minute continuity tolerance and a four-hour extension cap.

---

## File Map

```text
.gitignore                                      Generated/local artifacts
AGENTS.md                                       Project generation and test commands
README.md                                       Setup, privacy, and device-testing notes
generate.sh                                     XcodeGen entry point
project.yml                                     App, tests, HealthKit capability, Info.plist
Sources/App/SleepDaddyApp.swift                 App entry point and dependency composition
Sources/App/SleepDaddy.entitlements             HealthKit entitlement
Sources/Domain/SleepInterval.swift              App-owned stage, source, interval models
Sources/Domain/NightModels.swift                Night window, summary, conflict, viewport models
Sources/HealthKit/HealthKitSleepStore.swift     Authorization and category-sample queries
Sources/HealthKit/SleepSampleProviding.swift    Store protocol and fixture seam
Sources/SleepProcessing/SleepNormalizer.swift   Raw-value to domain-stage mapping
Sources/SleepProcessing/NightAssembler.swift    Filtering, boundaries, conflict lane, totals
Sources/Persistence/SleepPreferences.swift      Source/window/exclusion persistence
Sources/Features/NightBrowser/NightBrowserModel.swift
                                                Loading and selected-night state
Sources/Features/NightBrowser/NightBrowserView.swift
                                                Overview, detail, empty/error states
Sources/Features/NightBrowser/NightOverviewStrip.swift
                                                Nearby-night navigation
Sources/Features/NightBrowser/SleepSourceFilterView.swift
                                                Persistent multi-source selection
Sources/Features/NightBrowser/SleepRecordInspector.swift
                                                Provenance and exclusion controls
Sources/Features/Settings/SleepSettingsView.swift
                                                Core-window and excluded-record settings
Sources/Features/Timeline/SleepTimelineGeometry.swift
                                                Pure coordinate and viewport math
Sources/Features/Timeline/SleepTimelineCanvas.swift
                                                Drawing, pinch, pan, selection
Sources/Features/Timeline/SleepTimelineNavigator.swift
                                                Context range and coarse jumps
Sources/Features/Sharing/SleepShareView.swift    Chrome-free export composition
Sources/Features/Sharing/SleepShareRenderer.swift
                                                ImageRenderer and share item production
Sources/UI/SleepStageStyle.swift                 Colors, labels, symbols, accessibility names
Tests/Fixtures/SleepFixtures.swift               Deterministic raw/domain samples
Tests/SleepNormalizerTests.swift
Tests/NightAssemblerTests.swift
Tests/SleepPreferencesTests.swift
Tests/NightBrowserModelTests.swift
Tests/SleepTimelineGeometryTests.swift
Tests/SleepShareRendererTests.swift
Tests/SnapshotSupport.swift
Tests/Snapshots/                               Fixed timeline/share reference PNGs
```

---

### Task 1: Generated Project Foundation and HealthKit Capability

**Files:**
- Create: `.gitignore`
- Create: `AGENTS.md`
- Create: `README.md`
- Create: `generate.sh`
- Create: `project.yml`
- Create: `Sources/App/SleepDaddyApp.swift`
- Create: `Sources/App/SleepDaddy.entitlements`
- Create: `Sources/Features/NightBrowser/NightBrowserView.swift`
- Create: `Tests/AppSmokeTests.swift`

**Interfaces:**
- Consumes: none.
- Produces: `SleepDaddyApp`, `NightBrowserView`, the `SleepDaddy` application target, and the `SleepDaddyTests` test target.

- [ ] **Step 1: Write the project smoke test and minimal root view**

```swift
import SwiftUI
import Testing
@testable import SleepDaddy

@Suite struct AppSmokeTests {
    @Test @MainActor func rootViewCanBeCreated() {
        _ = NightBrowserView()
    }
}
```

```swift
import SwiftUI

struct NightBrowserView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "SleepDaddy",
                systemImage: "bed.double",
                description: Text("Preparing sleep data")
            )
            .navigationTitle("Sleep")
        }
    }
}
```

- [ ] **Step 2: Define the generated project and capabilities**

Use this essential `project.yml` shape:

```yaml
name: SleepDaddy
options:
  bundleIdPrefix: fm.rodeo
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    DEVELOPMENT_TEAM: 6HQGHHRK87
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: YES
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    STRING_CATALOG_GENERATE_SYMBOLS: YES
targets:
  SleepDaddy:
    type: application
    platform: iOS
    sources:
      - path: Sources
    entitlements:
      path: Sources/App/SleepDaddy.entitlements
      properties:
        com.apple.developer.healthkit: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: fm.rodeo.sleepdaddy
        INFOPLIST_KEY_CFBundleDisplayName: SleepDaddy
        CODE_SIGN_STYLE: Automatic
    info:
      path: Sources/Info.plist
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        ITSAppUsesNonExemptEncryption: false
        NSHealthShareUsageDescription: "SleepDaddy reads your sleep data to display detailed, zoomable timelines."
        UILaunchScreen:
          UIColorName: systemBackgroundColor
  SleepDaddyTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: SleepDaddy
schemes:
  SleepDaddy:
    build:
      targets:
        SleepDaddy: all
    run:
      debugEnabled: false
    test:
      targets:
        - SleepDaddyTests
```

Make `generate.sh` run `xcodegen generate` with `set -euo pipefail`. Ignore
`.DS_Store`, `.superpowers/`, `SleepDaddy.xcodeproj/`, `Sources/Info.plist`, and
`DerivedData/`.

- [ ] **Step 3: Generate and run the smoke test**

Run:

```bash
chmod +x generate.sh
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Expected: the project generates and `AppSmokeTests.rootViewCanBeCreated` passes.

- [ ] **Step 4: Commit the foundation**

```bash
git add .gitignore AGENTS.md README.md generate.sh project.yml Sources Tests/AppSmokeTests.swift
git commit -m "build: scaffold SleepDaddy iOS app"
```

---

### Task 2: Domain Models and Sleep Normalization

**Files:**
- Create: `Sources/Domain/SleepInterval.swift`
- Create: `Sources/Domain/NightModels.swift`
- Create: `Sources/HealthKit/SleepSampleProviding.swift`
- Create: `Sources/SleepProcessing/SleepNormalizer.swift`
- Create: `Tests/Fixtures/SleepFixtures.swift`
- Create: `Tests/SleepNormalizerTests.swift`

**Interfaces:**
- Consumes: none.
- Produces:
  - `RawSleepSample(id:start:end:value:source:)`
  - `SleepSource(id:name:)`
  - `SleepStage`
  - `SleepInterval(id:start:end:stage:source:)`
  - `SleepNormalizer.normalize(_:) -> [SleepInterval]`

- [ ] **Step 1: Write failing normalization tests**

```swift
import Foundation
import Testing
@testable import SleepDaddy

@Suite struct SleepNormalizerTests {
    @Test func mapsDetailedAndLegacyStages() {
        let source = SleepSource(id: "watch", name: "Apple Watch")
        let raw = [
            RawSleepSample(id: UUID(1), start: .hour(22), end: .hour(23),
                           value: SleepRawValue.asleepCore.rawValue, source: source),
            RawSleepSample(id: UUID(2), start: .hour(23), end: .hour(24),
                           value: SleepRawValue.legacyAsleep.rawValue, source: source)
        ]

        let result = SleepNormalizer().normalize(raw)

        #expect(result.map(\.stage) == [.core, .asleepUnspecified])
        #expect(result.map(\.source.id) == ["watch", "watch"])
    }

    @Test func rejectsZeroLengthSamples() {
        let sample = SleepFixtures.raw(startHour: 22, endHour: 22, value: .asleepDeep)
        #expect(SleepNormalizer().normalize([sample]).isEmpty)
    }
}
```

The fixture helpers define a fixed Gregorian calendar, `America/Chicago` time zone, January 15, 2026 anchor date, `UUID(_ integer:)`, and `Date.hour(_:)`.

- [ ] **Step 2: Run the tests and verify the missing-type failure**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/SleepNormalizerTests
```

Expected: compilation fails because the domain and normalizer types do not exist.

- [ ] **Step 3: Implement app-owned sendable models and normalization**

```swift
import Foundation

struct SleepSource: Hashable, Codable, Sendable, Identifiable {
    let id: String
    let name: String
}

enum SleepStage: String, CaseIterable, Codable, Sendable {
    case inBed, awake, core, deep, rem, asleepUnspecified

    var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .asleepUnspecified: true
        case .inBed, .awake: false
        }
    }
}

enum SleepRawValue: Int, Sendable {
    case inBed = 0
    case legacyAsleep = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepREM = 5
}

struct RawSleepSample: Hashable, Sendable, Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let value: Int
    let source: SleepSource
}

struct SleepInterval: Hashable, Sendable, Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let stage: SleepStage
    let source: SleepSource

    var duration: TimeInterval { end.timeIntervalSince(start) }
}
```

```swift
struct SleepNormalizer: Sendable {
    func normalize(_ samples: [RawSleepSample]) -> [SleepInterval] {
        samples.compactMap { sample in
            guard sample.end > sample.start else { return nil }
            return SleepInterval(
                id: sample.id,
                start: sample.start,
                end: sample.end,
                stage: stage(for: sample.value),
                source: sample.source
            )
        }
        .sorted { ($0.start, $0.end, $0.id.uuidString) < ($1.start, $1.end, $1.id.uuidString) }
    }

    private func stage(for value: Int) -> SleepStage {
        switch value {
        case SleepRawValue.inBed.rawValue: .inBed
        case SleepRawValue.awake.rawValue: .awake
        case SleepRawValue.asleepCore.rawValue: .core
        case SleepRawValue.asleepDeep.rawValue: .deep
        case SleepRawValue.asleepREM.rawValue: .rem
        default: .asleepUnspecified
        }
    }
}
```

- [ ] **Step 4: Run normalization tests**

Run the Task 2 test command again.

Expected: all `SleepNormalizerTests` pass.

- [ ] **Step 5: Commit domain normalization**

```bash
git add Sources/Domain Sources/HealthKit/SleepSampleProviding.swift Sources/SleepProcessing/SleepNormalizer.swift Tests/Fixtures Tests/SleepNormalizerTests.swift
git commit -m "feat: normalize HealthKit sleep samples"
```

---

### Task 3: Adaptive Night Assembly and Conflict Resolution

**Files:**
- Modify: `Sources/Domain/NightModels.swift`
- Create: `Sources/SleepProcessing/NightAssembler.swift`
- Create: `Tests/NightAssemblerTests.swift`

**Interfaces:**
- Consumes: `[SleepInterval]`, `Set<String>` selected source IDs, and `Set<UUID>` excluded IDs.
- Produces:
  - `NightWindow(labelDate:coreStart:coreEnd:searchStart:searchEnd:)`
  - `NightAssembly(intervals:resolvedSegments:conflicts:detectedStart:detectedEnd:summary:)`
  - `NightAssembler.assemble(intervals:window:selectedSourceIDs:excludedIDs:sourcePriority:)`

- [ ] **Step 1: Write failing boundary and filtering tests**

```swift
@Suite struct NightAssemblerTests {
    @Test func includesContiguousSixPMSleep() throws {
        let window = SleepFixtures.nightWindow()
        let intervals = [
            SleepFixtures.interval(18, 19, .core),
            SleepFixtures.interval(19, 22, .deep)
        ]

        let night = try #require(NightAssembler().assemble(
            intervals: intervals,
            window: window,
            selectedSourceIDs: ["watch"],
            excludedIDs: [],
            sourcePriority: ["watch"]
        ))

        #expect(night.detectedStart == .hour(18))
    }

    @Test func excludesGapGreaterThanThirtyMinutesAndMiddayNap() throws {
        let intervals = [
            SleepFixtures.interval(14, 15, .core),
            SleepFixtures.interval(18, 18.4, .core),
            SleepFixtures.interval(19, 22, .deep)
        ]
        let night = try #require(SleepFixtures.assemble(intervals))
        #expect(night.detectedStart == .hour(19))
        #expect(!night.intervals.contains { $0.start == .hour(14) })
    }

    @Test func thirtyMinuteGapIsContiguousAndFourHourCapWins() throws {
        let intervals = [
            SleepFixtures.interval(14, 18.5, .core),
            SleepFixtures.interval(19, 22, .deep)
        ]
        let night = try #require(SleepFixtures.assemble(intervals))
        #expect(night.detectedStart == .hour(15))
    }

    @Test func filtersSourcesAndExclusionsBeforeBoundaryDetection() throws {
        let excluded = SleepFixtures.interval(18, 22, .core, id: UUID(9), sourceID: "phone")
        let kept = SleepFixtures.interval(19, 22, .deep, sourceID: "watch")
        let night = try #require(SleepFixtures.assemble(
            [excluded, kept],
            sourceIDs: ["watch", "phone"],
            excludedIDs: [UUID(9)]
        ))
        #expect(night.detectedStart == .hour(19))
    }
}
```

- [ ] **Step 2: Run tests and verify the missing-assembler failure**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/NightAssemblerTests
```

Expected: compilation fails because `NightAssembler` and assembly models are absent.

- [ ] **Step 3: Implement boundary expansion and summary calculation**

Use half-open date ranges and this exact assembly order:

```swift
struct NightAssembler: Sendable {
    let gapTolerance: TimeInterval = 30 * 60
    let extensionCap: TimeInterval = 4 * 60 * 60

    func assemble(
        intervals: [SleepInterval],
        window: NightWindow,
        selectedSourceIDs: Set<String>,
        excludedIDs: Set<UUID>,
        sourcePriority: [String]
    ) -> NightAssembly? {
        let eligible = intervals.filter {
            selectedSourceIDs.contains($0.source.id) &&
            !excludedIDs.contains($0.id) &&
            $0.end > window.searchStart &&
            $0.start < window.searchEnd
        }
        let continuity = eligible.filter { $0.stage != .inBed }
        let seeds = eligible.filter {
            $0.stage.isAsleep &&
            $0.end > window.coreStart && $0.start < window.coreEnd
        }
        guard !seeds.isEmpty else { return nil }

        let earliest = max(
            window.coreStart.addingTimeInterval(-extensionCap),
            connectedStart(from: seeds, candidates: continuity)
        )
        let latest = min(
            window.coreEnd.addingTimeInterval(extensionCap),
            connectedEnd(from: seeds, candidates: continuity)
        )
        let included = eligible.filter { $0.end > earliest && $0.start < latest }
        let resolved = resolveDetailedLane(included, sourcePriority: sourcePriority)
        return NightAssembly.make(
            intervals: included,
            resolvedSegments: resolved.segments,
            conflicts: resolved.conflicts,
            detectedStart: earliest,
            detectedEnd: latest
        )
    }
}
```

Implement `connectedStart` and `connectedEnd` as iterative frontier expansion:
an interval joins when its gap from the current frontier is at most 1,800
seconds; repeat until the frontier stops moving. Clip returned resolved segments
to `detectedStart..<detectedEnd`. Calculate sleep totals from resolved
non-awake, non-in-bed segments so overlaps are never double-counted.

- [ ] **Step 4: Add conflict-resolution tests and implementation**

```swift
@Test func specificStageBeatsUnspecifiedAndDetailedBeatsInBed() throws {
    let night = try #require(SleepFixtures.assemble([
        SleepFixtures.interval(22, 23, .inBed, sourceID: "phone"),
        SleepFixtures.interval(22, 23, .asleepUnspecified, sourceID: "phone"),
        SleepFixtures.interval(22, 23, .deep, sourceID: "watch")
    ]))
    #expect(night.resolvedSegments.map(\.stage) == [.deep])
}

@Test func equalSpecificityUsesSourcePriorityAndReportsConflict() throws {
    let night = try #require(SleepFixtures.assemble(
        [
            SleepFixtures.interval(22, 23, .deep, sourceID: "watch"),
            SleepFixtures.interval(22, 23, .rem, sourceID: "phone")
        ],
        sourcePriority: ["phone", "watch"]
    ))
    #expect(night.resolvedSegments.map(\.stage) == [.rem])
    #expect(night.conflicts.count == 1)
}
```

Split at every unique interval boundary, choose the winning interval for each
slice by specificity then `sourcePriority`, merge adjacent slices with identical
stage and winner source, and retain all contributors in `SleepConflict`.

- [ ] **Step 5: Run assembler tests and the full suite**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/NightAssemblerTests
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Expected: all boundary, filtering, conflict, normalization, and smoke tests pass.

- [ ] **Step 6: Commit adaptive assembly**

```bash
git add Sources/Domain/NightModels.swift Sources/SleepProcessing/NightAssembler.swift Tests/NightAssemblerTests.swift Tests/Fixtures/SleepFixtures.swift
git commit -m "feat: assemble adaptive sleep nights"
```

---

### Task 4: HealthKit Read Store

**Files:**
- Modify: `Sources/HealthKit/SleepSampleProviding.swift`
- Create: `Sources/HealthKit/HealthKitSleepStore.swift`
- Create: `Tests/HealthKitSleepStoreMappingTests.swift`

**Interfaces:**
- Consumes: `HKCategorySample` values from `HKHealthStore`.
- Produces:
  - `SleepSampleProviding.requestAuthorization() async throws`
  - `SleepSampleProviding.fetchSamples(in: Range<Date>) async throws -> [RawSleepSample]`
  - `HealthKitSleepStore.map(_:) -> RawSleepSample`

- [ ] **Step 1: Define the protocol and failing mapping tests**

```swift
protocol SleepSampleProviding: Sendable {
    func requestAuthorization() async throws
    func fetchSamples(in range: Range<Date>) async throws -> [RawSleepSample]
}
```

```swift
@Suite struct HealthKitSleepStoreMappingTests {
    @Test func mapsUUIDDatesValueAndSourceRevision() throws {
        let sample = HealthKitFixtures.categorySample(
            value: SleepRawValue.asleepREM.rawValue,
            start: .hour(22),
            end: .hour(23),
            sourceName: "Watch Sleep",
            bundleID: "com.apple.health"
        )
        let raw = HealthKitSleepStore.map(sample)
        #expect(raw.id == sample.uuid)
        #expect(raw.value == SleepRawValue.asleepREM.rawValue)
        #expect(raw.source == SleepSource(id: "com.apple.health", name: "Watch Sleep"))
    }
}
```

- [ ] **Step 2: Run the mapping test and verify failure**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/HealthKitSleepStoreMappingTests
```

Expected: compilation fails because `HealthKitSleepStore` is absent.

- [ ] **Step 3: Implement read authorization and the date-range query**

```swift
import HealthKit

actor HealthKitSleepStore: SleepSampleProviding {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { throw SleepStoreError.healthDataUnavailable }
        try await healthStore.requestAuthorization(toShare: [], read: [type])
    }

    func fetchSamples(in range: Range<Date>) async throws -> [RawSleepSample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { throw SleepStoreError.sleepTypeUnavailable }
        let predicate = HKQuery.predicateForSamples(
            withStart: range.lowerBound,
            end: range.upperBound,
            options: []
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let mapped = (samples as? [HKCategorySample] ?? []).map(Self.map)
                continuation.resume(returning: mapped)
            }
            healthStore.execute(query)
        }
    }

    nonisolated static func map(_ sample: HKCategorySample) -> RawSleepSample {
        let source = sample.sourceRevision.source
        return RawSleepSample(
            id: sample.uuid,
            start: sample.startDate,
            end: sample.endDate,
            value: sample.value,
            source: SleepSource(
                id: source.bundleIdentifier,
                name: source.name
            )
        )
    }
}
```

If Swift 6 flags the callback capture, isolate the continuation bridge in a
private `@preconcurrency import HealthKit` file and keep only app-owned
`Sendable` values crossing the actor boundary.

- [ ] **Step 4: Run targeted and full tests**

Run the Task 4 command, then the full test command from Task 3.

Expected: mapping and existing tests pass. Authorization behavior remains part
of physical-device verification because simulator data is not authoritative.

- [ ] **Step 5: Commit HealthKit access**

```bash
git add Sources/HealthKit Tests/HealthKitSleepStoreMappingTests.swift
git commit -m "feat: read sleep samples from HealthKit"
```

---

### Task 5: Persistent Window, Source Filter, and Exclusions

**Files:**
- Create: `Sources/Persistence/SleepPreferences.swift`
- Create: `Tests/SleepPreferencesTests.swift`

**Interfaces:**
- Consumes: a `UserDefaults` suite.
- Produces:
  - `SleepPreferences.snapshot() -> SleepPreferenceSnapshot`
  - `SleepPreferences.setNightWindow(startMinutes:endMinutes:)`
  - `SleepPreferences.setSelectedSourceIDs(_:)`
  - `SleepPreferences.exclude(_:)`
  - `SleepPreferences.restore(_:)`

- [ ] **Step 1: Write failing persistence and default tests**

```swift
@Suite struct SleepPreferencesTests {
    @Test func defaultsToSevenPMThroughSevenAM() {
        let preferences = SleepFixtures.preferences()
        let snapshot = preferences.snapshot()
        #expect(snapshot.startMinutes == 19 * 60)
        #expect(snapshot.endMinutes == 7 * 60)
    }

    @Test func persistsSourceOrderAndExclusions() {
        let defaults = SleepFixtures.defaults()
        let first = SleepPreferences(defaults: defaults)
        first.setSelectedSourceIDs(["watch", "phone"])
        first.exclude(UUID(7))

        let restored = SleepPreferences(defaults: defaults).snapshot()
        #expect(restored.selectedSourceIDs == ["watch", "phone"])
        #expect(restored.excludedIDs == [UUID(7)])
    }
}
```

- [ ] **Step 2: Run tests and verify the missing-preferences failure**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/SleepPreferencesTests
```

- [ ] **Step 3: Implement explicit Codable persistence**

```swift
struct SleepPreferenceSnapshot: Codable, Equatable, Sendable {
    var startMinutes = 19 * 60
    var endMinutes = 7 * 60
    var selectedSourceIDs: [String] = []
    var excludedIDs: Set<UUID> = []
}

final class SleepPreferences {
    private let defaults: UserDefaults
    private let key = "sleep-preferences-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> SleepPreferenceSnapshot {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(SleepPreferenceSnapshot.self, from: data)
        else { return SleepPreferenceSnapshot() }
        return value
    }

    private func update(_ mutation: (inout SleepPreferenceSnapshot) -> Void) {
        var value = snapshot()
        mutation(&value)
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
```

Implement the five public mutators using `update`. Preserve source order because
the assembler uses it as deterministic conflict priority. Validate start and end
minutes as `0...1439` and reject an equal start/end window.

- [ ] **Step 4: Run preferences and full tests**

Expected: a fresh suite returns 7:00 PM–7:00 AM, and a second preferences
instance restores sources and exclusions.

- [ ] **Step 5: Commit local preferences**

```bash
git add Sources/Persistence Tests/SleepPreferencesTests.swift
git commit -m "feat: persist sleep filters and exclusions"
```

---

### Task 6: Night Browser State and Buffered Loading

**Files:**
- Create: `Sources/Features/NightBrowser/NightBrowserModel.swift`
- Create: `Tests/NightBrowserModelTests.swift`
- Modify: `Tests/Fixtures/SleepFixtures.swift`

**Interfaces:**
- Consumes: `SleepSampleProviding`, `SleepNormalizer`, `NightAssembler`, `SleepPreferences`, and `Calendar`.
- Produces:
  - `NightBrowserState`
  - `NightBrowserModel.load() async`
  - `NightBrowserModel.selectNight(_:)`
  - `NightBrowserModel.setSelectedSources(_:)`
  - `NightBrowserModel.exclude(_:)`
  - `NightBrowserModel.restore(_:)`
  - `NightBrowserModel.updateViewport(_:)`

- [ ] **Step 1: Write failing model tests**

```swift
@Suite @MainActor struct NightBrowserModelTests {
    @Test func loadsBufferedNightsAndSelectsMostRecentPopulatedNight() async {
        let store = FixtureSleepStore(samples: SleepFixtures.threeNights())
        let model = SleepFixtures.browserModel(store: store)

        await model.load()

        #expect(store.requestedRanges.count == 1)
        #expect(model.state.nights.count == 14)
        #expect(model.state.selectedNight?.labelDate == SleepFixtures.january(15))
        #expect(model.state.selectedSources == ["watch"])
    }

    @Test func sourceChangePersistsAndReassemblesWithoutRefetch() async {
        let store = FixtureSleepStore(samples: SleepFixtures.conflictingSources())
        let model = SleepFixtures.browserModel(store: store)
        await model.load()

        model.setSelectedSources(["watch"])

        #expect(store.requestedRanges.count == 1)
        #expect(model.state.selectedSources == ["watch"])
        #expect(model.state.selectedNight?.conflicts.isEmpty == true)
    }
}
```

- [ ] **Step 2: Run tests and verify the missing-model failure**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/NightBrowserModelTests
```

- [ ] **Step 3: Implement observable browser state**

```swift
enum NightBrowserPhase: Equatable {
    case idle, authorizing, loading, loaded, unavailable, noReadableData
    case failed(String)
}

struct TimelineViewport: Equatable, Sendable {
    var start: Date
    var end: Date
}

@MainActor @Observable
final class NightBrowserModel {
    private let store: any SleepSampleProviding
    private let normalizer: SleepNormalizer
    private let assembler: NightAssembler
    private let preferences: SleepPreferences
    private let calendar: Calendar
    private var normalized: [SleepInterval] = []

    private(set) var state = NightBrowserState()

    func load() async {
        state.phase = .authorizing
        do {
            try await store.requestAuthorization()
            state.phase = .loading
            let windows = makeFourteenWindows(endingAt: Date())
            let range = windows.first!.searchStart..<windows.last!.searchEnd
            normalized = normalizer.normalize(try await store.fetchSamples(in: range))
            reassemble(windows: windows, selectMostRecentIfNeeded: true)
            state.phase = state.nights.contains(where: \.isPopulated) ? .loaded : .noReadableData
        } catch SleepStoreError.healthDataUnavailable {
            state.phase = .unavailable
        } catch {
            state.phase = .failed(error.localizedDescription)
        }
    }
}
```

`makeFourteenWindows` returns oldest-to-newest windows, each with a four-hour
buffer. `reassemble` creates empty `NightPresentation` values for dates without
a seed. After the first fetch, an empty persisted source selection is initialized
to every discovered source ordered by localized name then identifier and is
persisted; a nonempty persisted selection is preserved. Source changes and
exclusion changes call `reassemble` against cached normalized data and reset the
viewport to the selected night's detected range.

- [ ] **Step 4: Add tests for exclusions, empty dates, and neutral permission copy**

```swift
@Test func exclusionAndRestoreReassembleWithoutRefetch() async throws {
    let sample = SleepFixtures.interval(22, 23, .deep, id: UUID(7))
    let store = FixtureSleepStore(samples: [SleepFixtures.raw(from: sample)])
    let model = SleepFixtures.browserModel(store: store)
    await model.load()
    let originalTotal = try #require(model.state.selectedNight?.summary.totalSleep)

    model.exclude(UUID(7))
    #expect(model.state.selectedNight?.summary.totalSleep == 0)
    model.restore(UUID(7))

    #expect(model.state.selectedNight?.summary.totalSleep == originalTotal)
    #expect(store.requestedRanges.count == 1)
}

@Test func emptyDatesRemainNavigableAndCopyIsNeutral() async {
    let model = SleepFixtures.browserModel(store: FixtureSleepStore(samples: []))
    await model.load()
    #expect(model.state.nights.count == 14)
    #expect(model.state.phase == .noReadableData)
    #expect(!model.state.guidance.localizedCaseInsensitiveContains("denied"))
}
```

- [ ] **Step 5: Run model and full tests**

Expected: all browser state transitions and prior suites pass.

- [ ] **Step 6: Commit browsing state**

```bash
git add Sources/Features/NightBrowser/NightBrowserModel.swift Tests/NightBrowserModelTests.swift Tests/Fixtures/SleepFixtures.swift
git commit -m "feat: load and browse assembled sleep nights"
```

---

### Task 7: Timeline Geometry, Canvas, Gestures, and Navigator

**Files:**
- Create: `Sources/UI/SleepStageStyle.swift`
- Create: `Sources/Features/Timeline/SleepTimelineGeometry.swift`
- Create: `Sources/Features/Timeline/SleepTimelineCanvas.swift`
- Create: `Sources/Features/Timeline/SleepTimelineNavigator.swift`
- Create: `Tests/SleepTimelineGeometryTests.swift`

**Interfaces:**
- Consumes: `NightAssembly`, `TimelineViewport`, selected interval ID, and callbacks for viewport/selection.
- Produces:
  - `SleepTimelineGeometry.x(for:in:)`
  - `SleepTimelineGeometry.date(atX:in:)`
  - `SleepTimelineGeometry.rect(for:stage:viewport:size:)`
  - `SleepTimelineGeometry.zoom(viewport:scale:anchor:bounds:)`
  - `SleepTimelineGeometry.pan(viewport:seconds:bounds:)`
  - `SleepTimelineCanvas`
  - `SleepTimelineNavigator`

- [ ] **Step 1: Write failing geometry and viewport tests**

```swift
@Suite struct SleepTimelineGeometryTests {
    @Test func mapsVisibleBoundsAndRoundTripsDates() {
        let viewport = TimelineViewport(start: .hour(22), end: .hour(30))
        let geometry = SleepTimelineGeometry(size: CGSize(width: 320, height: 240))
        #expect(geometry.x(for: .hour(22), in: viewport) == 0)
        #expect(geometry.x(for: .hour(30), in: viewport) == 320)
        #expect(abs(geometry.date(atX: 120, in: viewport).timeIntervalSince(.hour(25))) < 0.001)
    }

    @Test func zoomAnchorsAndClampsToDetectedBounds() {
        let bounds = TimelineViewport(start: .hour(18), end: .hour(31))
        let viewport = TimelineViewport(start: .hour(22), end: .hour(30))
        let zoomed = SleepTimelineGeometry.zoom(
            viewport: viewport,
            scale: 2,
            anchor: .hour(26),
            bounds: bounds
        )
        #expect(zoomed == TimelineViewport(start: .hour(24), end: .hour(28)))
    }

    @Test func minimumViewportIsFifteenMinutes() {
        let result = SleepTimelineGeometry.zoom(
            viewport: TimelineViewport(start: .hour(22), end: .hour(23)),
            scale: 20,
            anchor: .hour(22.5),
            bounds: TimelineViewport(start: .hour(18), end: .hour(31))
        )
        #expect(result.end.timeIntervalSince(result.start) == 15 * 60)
    }
}
```

- [ ] **Step 2: Run geometry tests and verify failure**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:SleepDaddyTests/SleepTimelineGeometryTests
```

- [ ] **Step 3: Implement pure geometry and stage styling**

Use six fixed rows ordered awake, REM, core, deep, asleep unspecified, and in
bed. `SleepStageStyle` provides a localized label, system color, hatch/symbol
fallback, and accessibility name for every stage.
Define `SleepStageLegend` in `SleepStageStyle.swift` as a wrapping horizontal
view built from the stages present in the current assembly.

Implement date-to-x as:

```swift
let fraction = date.timeIntervalSince(viewport.start) /
    viewport.end.timeIntervalSince(viewport.start)
return size.width * fraction
```

Clamp pan and zoom to detected bounds. Enforce a 15-minute minimum visible
duration and never allow a viewport wider than detected bounds.

- [ ] **Step 4: Build the Canvas and navigator**

```swift
struct SleepTimelineCanvas: View {
    let assembly: NightAssembly
    @Binding var viewport: TimelineViewport
    @Binding var selectedIntervalID: UUID?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let geometry = SleepTimelineGeometry(size: size)
                drawRows(in: &context, geometry: geometry)
                drawIntervals(in: &context, geometry: geometry)
                drawAxis(in: &context, geometry: geometry)
            }
            .contentShape(Rectangle())
            .gesture(magnificationGesture(size: proxy.size))
            .simultaneousGesture(panGesture(size: proxy.size))
            .accessibilityRepresentation {
                SleepIntervalAccessibilityList(
                    intervals: assembly.resolvedSegments,
                    selection: $selectedIntervalID
                )
            }
        }
    }
}
```

Keep gesture-start viewport state so magnification and drag deltas are always
calculated from the start of the active gesture. The navigator draws the entire
detected range and overlays the current viewport. Tapping or dragging its
highlight changes the center while preserving visible duration. Reset assigns
`detectedStart..<detectedEnd`.

Define `SleepIntervalAccessibilityList` as a private sibling view in
`SleepTimelineCanvas.swift`; it creates chronological buttons whose labels
contain stage, exact times, duration, source, and conflict count.

- [ ] **Step 5: Add hit-testing and navigator synchronization tests**

```swift
@Test func hitTestingSelectsOnlyVisibleSegmentRects() {
    let segment = SleepFixtures.interval(22, 23, .deep, id: UUID(4))
    let geometry = SleepTimelineGeometry(size: CGSize(width: 320, height: 240))
    let viewport = TimelineViewport(start: .hour(21), end: .hour(29))
    #expect(geometry.hitTest(
        CGPoint(x: 60, y: geometry.midY(for: .deep)),
        segments: [segment],
        viewport: viewport
    ) == UUID(4))
    #expect(geometry.hitTest(
        CGPoint(x: 300, y: 5),
        segments: [segment],
        viewport: viewport
    ) == nil)
}

@Test func navigatorMovePreservesDurationAndResetUsesBounds() {
    let bounds = TimelineViewport(start: .hour(18), end: .hour(31))
    let viewport = TimelineViewport(start: .hour(22), end: .hour(26))
    let moved = SleepTimelineGeometry.center(viewport, at: .hour(29), bounds: bounds)
    #expect(moved.end.timeIntervalSince(moved.start) == 4 * 60 * 60)
    #expect(SleepTimelineGeometry.reset(to: bounds) == bounds)
}
```

- [ ] **Step 6: Run timeline and full tests**

Expected: coordinate, hit-testing, zoom, pan, navigator, normalization, assembly,
preferences, and model tests pass.

- [ ] **Step 7: Commit the timeline**

```bash
git add Sources/UI Sources/Features/Timeline Tests/SleepTimelineGeometryTests.swift
git commit -m "feat: add zoomable sleep timeline"
```

---

### Task 8: Multi-Night UI, Filters, Inspection, Settings, and Accessibility

**Files:**
- Modify: `Sources/App/SleepDaddyApp.swift`
- Replace: `Sources/Features/NightBrowser/NightBrowserView.swift`
- Create: `Sources/Features/NightBrowser/NightOverviewStrip.swift`
- Create: `Sources/Features/NightBrowser/SleepSourceFilterView.swift`
- Create: `Sources/Features/NightBrowser/SleepRecordInspector.swift`
- Create: `Sources/Features/Settings/SleepSettingsView.swift`
- Create: `Tests/NightPresentationTests.swift`

**Interfaces:**
- Consumes: `NightBrowserModel` and timeline components.
- Produces: the complete read-only browsing, filtering, exclusion, restoration, settings, empty-state, and interval-inspection experience.

- [ ] **Step 1: Write failing presentation tests**

```swift
@Suite struct NightPresentationTests {
    @Test func conflictInspectorListsEveryContributor() throws {
        let conflict = SleepFixtures.deepREMConflict()
        let rows = SleepRecordInspectorModel(conflict: conflict).rows
        #expect(rows.map(\.sourceName) == ["Apple Watch", "Phone"])
        #expect(rows.map(\.stage) == [.deep, .rem])
    }

    @Test func noReadableDataCopyDoesNotClaimDenial() {
        let copy = NightBrowserCopy.message(for: .noReadableData)
        #expect(!copy.localizedCaseInsensitiveContains("denied"))
        #expect(copy.contains("Health"))
    }
}
```

- [ ] **Step 2: Run presentation tests and verify failure**

Run the targeted suite using the same xcodebuild pattern as earlier tasks.

- [ ] **Step 3: Compose the main browsing screen**

```swift
struct NightBrowserView: View {
    @State var model: NightBrowserModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.state.phase {
                case .loaded:
                    ScrollView {
                        NightOverviewStrip(
                            nights: model.state.nights,
                            selection: selectedNightBinding
                        )
                        SleepSourceFilterView(
                            sources: model.state.availableSources,
                            selection: sourceSelectionBinding
                        )
                        selectedNightContent
                    }
                default:
                    phaseView
                }
            }
            .navigationTitle("Sleep")
            .toolbar { settingsToolbar }
            .task { await model.load() }
        }
    }
}
```

The overview strip shows 14 horizontally scrollable nights, a duration bar,
compact stage colors, weekday/date labels, a selected outline, and an explicit
empty-night appearance. Selecting a date updates the detail without fetching.

- [ ] **Step 4: Add filters, inspector, exclusions, and settings**

The source filter is a multi-select sheet ordered by the persisted priority. Do
not allow deselecting the final source while readable sources exist. The
inspector displays stage, exact start/end, duration, source, and every conflict
contributor; its Exclude action calls `model.exclude(id)`.

Settings uses two `DatePicker` controls reduced to time components and validates
that start and end differ. “Excluded Records” lists IDs that still match loaded
samples with date, time, stage, and source; Restore calls `model.restore(id)`.

- [ ] **Step 5: Add accessibility semantics**

Provide:

- Chronological `Button` elements for every visible interval in
  `accessibilityRepresentation`.
- Stage, time, duration, source, and conflict count in each interval label.
- Non-color stage markers from `SleepStageStyle`.
- Selected-night and empty-night values in the overview.
- Explicit labels and values for Reset, Share, navigator range, source count,
  Exclude, and Restore.
- Dynamic Type layouts that avoid fixed text heights.

- [ ] **Step 6: Run tests and simulator build**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Expected: all tests and the simulator build pass.

- [ ] **Step 7: Commit the complete browsing UI**

```bash
git add Sources/App Sources/Features/NightBrowser Sources/Features/Settings Tests/NightPresentationTests.swift
git commit -m "feat: add sleep browsing and filtering UI"
```

---

### Task 9: Current-Viewport Image Sharing and Snapshots

**Files:**
- Create: `Sources/Features/Sharing/SleepShareView.swift`
- Create: `Sources/Features/Sharing/SleepShareRenderer.swift`
- Modify: `Sources/Features/NightBrowser/NightBrowserView.swift`
- Create: `Tests/SleepShareRendererTests.swift`
- Create: `Tests/SnapshotSupport.swift`
- Create: `Tests/Snapshots/share-dark-3x.png`
- Create: `Tests/Snapshots/timeline-light-3x.png`
- Modify: `project.yml`

**Interfaces:**
- Consumes: selected `NightPresentation`, `TimelineViewport`, selected sources, and `SleepStageStyle`.
- Produces:
  - `SleepShareContext(date:visibleRange:sourceDescription:segments:)`
  - `SleepShareRenderer.render(_:) throws -> UIImage`
  - Standard iOS share sheet presentation.

- [ ] **Step 1: Write failing share-context tests**

```swift
@Suite @MainActor struct SleepShareRendererTests {
    @Test func contextMatchesViewportAndSelectedSources() throws {
        let context = SleepFixtures.shareContext(
            viewport: .init(start: .hour(23.5), end: .hour(27.5)),
            sources: ["Apple Watch"]
        )
        #expect(context.visibleRange.start == .hour(23.5))
        #expect(context.visibleRange.end == .hour(27.5))
        #expect(context.sourceDescription == "Apple Watch")
        #expect(context.segments.allSatisfy {
            $0.end > context.visibleRange.start && $0.start < context.visibleRange.end
        })
    }

    @Test func renderedImageHasFixedShareWidthAndNoTotals() throws {
        let renderer = SleepShareRenderer(scale: 3)
        let image = try renderer.render(SleepFixtures.shareContext())
        #expect(image.size.width == 1200)
        #expect(SleepShareView.includesFullNightTotals == false)
    }
}
```

- [ ] **Step 2: Run share tests and verify failure**

Run the targeted suite using xcodebuild.

- [ ] **Step 3: Implement the dedicated share composition**

```swift
struct SleepShareView: View {
    static let includesFullNightTotals = false
    let context: SleepShareContext

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.title.bold())
            Text(context.visibleRange.formatted)
            Text("Sources: \(context.sourceDescription)")
            SleepTimelineCanvas(
                assembly: context.shareAssembly,
                viewport: .constant(context.visibleRange),
                selectedIntervalID: .constant(nil)
            )
            .frame(height: 420)
            SleepStageLegend(stages: context.presentStages)
        }
        .padding(40)
        .frame(width: 1200)
        .background(Color(uiColor: .systemBackground))
    }
}
```

The share view contains no buttons, navigation chrome, personal identifiers, or
full-night aggregate totals.

- [ ] **Step 4: Render with ImageRenderer and present the share sheet**

```swift
@MainActor
struct SleepShareRenderer {
    let scale: CGFloat

    func render(_ context: SleepShareContext) throws -> UIImage {
        let renderer = ImageRenderer(content: SleepShareView(context: context))
        renderer.scale = scale
        guard let image = renderer.uiImage else {
            throw SleepShareError.renderFailed
        }
        return image
    }
}
```

Use a `ShareLink` with a temporary PNG URL or a small `UIActivityViewController`
representable receiving the `UIImage`. On failure, retain viewport state and
show a retryable alert.

- [ ] **Step 5: Add deterministic snapshot support**

Configure fixed `en_US_POSIX` locale, `America/Chicago` time zone, 3x scale,
1,200-point share width, fixed light/dark color schemes, and fixture dates.
`SnapshotSupport.assertPNG` loads the named test resource, compares dimensions,
then computes per-channel absolute differences and requires at least 99.5% of
pixels to differ by no more than 2/255. A `RECORD_SNAPSHOTS=1` test environment
variable writes the initial reference PNG; normal test runs never modify it.

Add snapshot resources under the test target in `project.yml`, record once,
inspect both PNGs, then rerun without `RECORD_SNAPSHOTS`.

```swift
@Test func shareDarkSnapshotMatches() throws {
    let image = try SleepShareRenderer(scale: 3).render(
        SleepFixtures.shareContext(colorScheme: .dark)
    )
    try SnapshotSupport.assertPNG(
        image,
        named: "share-dark-3x",
        allowedChannelDelta: 2,
        requiredMatchingFraction: 0.995
    )
}
```

- [ ] **Step 6: Run share tests, snapshots, and full suite**

Run:

```bash
./generate.sh
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Expected: context, render, snapshot, and all prior tests pass.

- [ ] **Step 7: Commit image sharing**

```bash
git add project.yml Sources/Features/Sharing Sources/Features/NightBrowser/NightBrowserView.swift Tests/SleepShareRendererTests.swift Tests/SnapshotSupport.swift Tests/Snapshots
git commit -m "feat: share the visible sleep timeline"
```

---

### Task 10: Documentation and Release-Level Verification

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: the completed application.
- Produces: reproducible setup, simulator verification, and physical-device acceptance instructions.

- [ ] **Step 1: Document generation, testing, privacy, and device setup**

Add these exact commands:

```bash
./generate.sh
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Document that HealthKit authorization and personal sleep data require a signed
physical-device run, that SleepDaddy requests read-only sleep access, that
exclusions are local, and that no sleep records leave the device unless the user
explicitly shares an exported image.

- [ ] **Step 2: Run static repository checks**

Run:

```bash
rg -n "HKHealthStore|save\\(|delete\\(" Sources
rg -n "URLSession|Analytics|Firebase|Mixpanel" Sources project.yml
git diff --check
```

Expected: HealthKit usage is confined to the read store; there are no
HealthKit save/delete calls, networking clients, or analytics SDKs; whitespace
checks pass.

- [ ] **Step 3: Run the complete automated verification**

Run:

```bash
./generate.sh
xcodebuild clean build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Expected: clean build succeeds and every Swift Testing suite passes.

- [ ] **Step 4: Perform physical-device acceptance**

On a signed iPhone build:

1. Grant read-only sleep permission.
2. Confirm 14-night navigation and empty-night behavior.
3. Verify Apple Watch and other source names, selection persistence, and conflict details.
4. Confirm a 6:00 PM contiguous start is included while a disconnected midday nap is excluded.
5. Exclude a sample, relaunch, confirm it remains excluded, then restore it.
6. Pinch to the 15-minute minimum, pan to both boundaries, use navigator jumps, and Reset.
7. Use VoiceOver to traverse intervals chronologically and hear stage, exact time, duration, source, and conflict count.
8. Share a zoomed viewport and paste it into Messages and Notes.
9. Confirm the image includes date, visible range, source context, timeline, and legend, with no controls, identifiers, or full-night totals.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md AGENTS.md
git commit -m "docs: add SleepDaddy verification guide"
```
