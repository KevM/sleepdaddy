import Testing
import SwiftUI
@testable import SleepDaddy

/// Composition tests for the timeline views.
///
/// These deliberately do *not* compare against reference PNGs. Pixel-exact baselines went
/// stale on every font, spacing, or OS change, and the only available response was to
/// re-record them — so a red test meant "re-record me", not "look at me", and stopped
/// carrying information. What is still worth asserting is that each composition assembles
/// its fixture, reaches the state the view expects, and rasterizes at its intended size.
@Suite(.serialized)
struct SnapshotTests {
    /// Renders `view` and fails if SwiftUI could not produce a bitmap.
    ///
    /// When `expecting` is supplied, the rasterized pixel dimensions must match that size
    /// scaled by `scale` — this catches a view that silently collapses to zero height.
    @MainActor
    private func renderComposition(
        of view: some View,
        named name: String,
        expecting size: CGSize? = nil,
        scale: CGFloat = 2.0
    ) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.uiImage, let cgImage = image.cgImage else {
            Issue.record("Failed to render \(name)")
            return
        }

        guard let size else {
            #expect(cgImage.width > 0, "\(name) rendered zero width")
            #expect(cgImage.height > 0, "\(name) rendered zero height")
            return
        }

        #expect(cgImage.width == Int(size.width * scale), "\(name) width")
        #expect(cgImage.height == Int(size.height * scale), "\(name) height")
    }

    @Test @MainActor func testTimelineCardSnapshotComposition() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "s1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(7200), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s2", startDate: coreStart.addingTimeInterval(7200), endDate: coreStart.addingTimeInterval(14400), stage: .deep, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s3", startDate: coreStart.addingTimeInterval(14400), endDate: coreStart.addingTimeInterval(18000), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health")
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )

        let shareCard = ShareTimelineCardView(
            night: night,
            viewportStart: night.detectedStart,
            viewportEnd: night.detectedEnd,
            sourceFilterDescription: "Apple Watch"
        )
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        // The card fixes its own width and sizes its height to content, so only the
        // width is a known invariant here.
        renderComposition(of: shareCard, named: "share card")
    }

    @MainActor
    @Test func nightHeaderDateFormattingUsesExplicitLocaleAndTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-07-25T12:00:00Z")!
        let formatted = NightHeaderView.formattedDate(
            date,
            locale: Locale(identifier: "fr_FR"),
            timeZone: TimeZone(secondsFromGMT: 14 * 3600)!
        )

        #expect(formatted == "dim., juil. 26")
    }

    @Test @MainActor func testNightHeaderSnapshotComposition() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "s1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(7200), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s2", startDate: coreStart.addingTimeInterval(7200), endDate: coreStart.addingTimeInterval(14400), stage: .deep, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s3", startDate: coreStart.addingTimeInterval(14400), endDate: coreStart.addingTimeInterval(18000), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health")
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )

        let headerView = NightHeaderView(
            night: night,
            canGoPrevious: true,
            canGoNext: true,
            onPrevious: {},
            onNext: {},
            onSelectDate: { _ in }
        )
        .frame(width: 393, height: 60)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        renderComposition(
            of: headerView,
            named: "night header",
            expecting: CGSize(width: 393, height: 60)
        )
    }

    @Test @MainActor func landscapeToolbarRendersAtNarrowLandscapeWidth() {
        let locale = Locale(identifier: "en_US")
        let timeZone = TimeZone(secondsFromGMT: -12 * 3600)!
        let night = makeFixtureNight()
        let toolbar = LandscapeNightToolbarView(
            night: night,
            dateRange: nil,
            canGoPrevious: true,
            canGoNext: false,
            onPrevious: {},
            onNext: {},
            onSelectDate: { _ in }
        )
        .environment(\.locale, locale)
        .environment(\.timeZone, timeZone)
        .frame(width: 320, height: 44)

        renderComposition(
            of: toolbar,
            named: "narrow landscape toolbar",
            expecting: CGSize(width: 320, height: 44)
        )
    }

    @Test func landscapeToolbarSemanticsDescribeNavigationState() {
        let previous = LandscapeNightToolbarSemantics.previous(isEnabled: true)
        let next = LandscapeNightToolbarSemantics.next(isEnabled: false)
        let date = LandscapeNightToolbarSemantics.date(label: "Sat, Jul 25")
        let duration = LandscapeNightToolbarSemantics.duration(value: "4h 30m")

        #expect(previous.label == "Previous night")
        #expect(previous.hint == "Switches to the previous night")
        #expect(previous.isEnabled)
        #expect(next.label == "Next night")
        #expect(next.hint == "Switches to the next night")
        #expect(!next.isEnabled)
        #expect(date.label == "Sat, Jul 25")
        #expect(date.hint == "Double tap to choose a date")
        #expect(duration.label == "Sleep duration, 4h 30m")
    }

    @Test @MainActor func testSleepTimelineCanvasSnapshotComposition() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "inbed", startDate: coreStart, endDate: coreStart.addingTimeInterval(12 * 3600), stage: .inBed, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(5400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "core1", startDate: coreStart.addingTimeInterval(5400), endDate: coreStart.addingTimeInterval(10800), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "unspecified1", startDate: coreStart.addingTimeInterval(10800), endDate: coreStart.addingTimeInterval(16200), stage: .asleepUnspecified, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "rem1", startDate: coreStart.addingTimeInterval(16200), endDate: coreStart.addingTimeInterval(21600), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk2", startDate: coreStart.addingTimeInterval(21600), endDate: coreStart.addingTimeInterval(23400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "conflict_oura", startDate: coreStart.addingTimeInterval(12600), endDate: coreStart.addingTimeInterval(14400), stage: .core, sourceName: "Oura Ring", sourceIdentifier: "com.oura.ring")
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )
        let selectedUnspecifiedID = night.primaryLaneIntervals.first {
            $0.stage == .asleepUnspecified
        }!.id

        let canvas = SleepTimelineCanvas(
            night: night,
            viewportStart: night.detectedStart,
            viewportEnd: night.detectedEnd,
            selectedIntervalID: selectedUnspecifiedID,
            onSelectInterval: { _ in },
            onUpdateViewport: { _, _ in }
        )
        .frame(width: 393, height: 320)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.timelineInteractionEnabled, false)

        renderComposition(
            of: canvas,
            named: "timeline canvas",
            expecting: CGSize(width: 393, height: 320)
        )
    }

    @Test @MainActor func testCanvasSnapshotWithBriefAwakesHidden() {
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

        renderComposition(
            of: canvas,
            named: "canvas with brief awakes hidden",
            expecting: CGSize(width: 393, height: 320)
        )
    }

    @Test @MainActor func testSnapshotUnspecifiedOnlyNight() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(
                id: "unspecified1",
                startDate: coreStart.addingTimeInterval(3600),
                endDate: coreStart.addingTimeInterval(7 * 3600),
                stage: .asleepUnspecified,
                sourceName: "Basic Tracker",
                sourceIdentifier: "com.basic.tracker"
            )
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )

        #expect(night.hasSleepData)
        #expect(night.summary.stagePercentages.isEmpty)

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

        renderComposition(
            of: canvas,
            named: "unspecified-only canvas",
            expecting: CGSize(width: 393, height: 320)
        )
    }

    @Test @MainActor func testCompactSourceFilterButtonSnapshotComposition() {
        let filterButton = CompactSourceFilterButton(
            availableSources: ["com.apple.health": "Apple Watch", "com.oura.ring": "Oura Ring"],
            selectedSourceIDs: ["com.apple.health"],
            hidesBriefAwakes: false,
            onToggleSource: { _ in },
            onClearFilter: {},
            onToggleHideBriefAwakes: {}
        )
        .frame(width: 44, height: 44)
        .environment(\.colorScheme, .dark)

        renderComposition(
            of: filterButton,
            named: "compact source filter button",
            expecting: CGSize(width: 44, height: 44)
        )
    }

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

    private func makeFixtureNight() -> AssembledNight {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "inbed", startDate: coreStart, endDate: coreStart.addingTimeInterval(12 * 3600), stage: .inBed, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(5400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "core1", startDate: coreStart.addingTimeInterval(5400), endDate: coreStart.addingTimeInterval(10800), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "deep1", startDate: coreStart.addingTimeInterval(10800), endDate: coreStart.addingTimeInterval(16200), stage: .deep, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "rem1", startDate: coreStart.addingTimeInterval(16200), endDate: coreStart.addingTimeInterval(21600), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk2", startDate: coreStart.addingTimeInterval(21600), endDate: coreStart.addingTimeInterval(23400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "conflict_oura", startDate: coreStart.addingTimeInterval(12600), endDate: coreStart.addingTimeInterval(14400), stage: .core, sourceName: "Oura Ring", sourceIdentifier: "com.oura.ring")
        ]

        let assembler = NightAssembler()
        return assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )
    }

    @MainActor
    private func assertComposition(
        of view: some View,
        named name: String,
        width: CGFloat,
        height: CGFloat
    ) {
        let host = view
            .frame(width: width, height: height)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .environment(\.timelineInteractionEnabled, false)

        renderComposition(
            of: host,
            named: name,
            expecting: CGSize(width: width, height: height)
        )
    }

    @Test @MainActor func testSnapshotPortraitLightMode() {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .light)
        assertComposition(of: composite, named: "portrait light", width: 393, height: 520)
    }

    @Test @MainActor func testSnapshotPortraitDarkMode() {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
        assertComposition(of: composite, named: "portrait dark", width: 393, height: 520)
    }

    @Test @MainActor func testSnapshotLandscape() {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
        assertComposition(of: composite, named: "landscape", width: 852, height: 460)
    }

    @Test @MainActor func testSnapshotDynamicType() {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .accessibility2)
        assertComposition(of: composite, named: "dynamic type", width: 393, height: 600)
    }

    @Test @MainActor func testSnapshotReduceMotion() {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
            .environment(\.accessibilityReduceMotionOverride, true)
        assertComposition(of: composite, named: "reduce motion", width: 393, height: 520)
    }

    @Test func compactHeightSelectsImmersiveLandscapeLayout() {
        #expect(SelectedNightLayoutMode.resolve(verticalSizeClass: .compact) == .immersiveLandscape)
        #expect(SelectedNightLayoutMode.resolve(verticalSizeClass: .regular) == .standard)
        #expect(SelectedNightLayoutMode.resolve(verticalSizeClass: nil) == .standard)
    }
}

private struct NightDetailCompositeView: View {
    let night: AssembledNight

    var body: some View {
        VStack(spacing: 12) {
            NightHeaderView(
                night: night,
                canGoPrevious: true,
                canGoNext: true,
                onPrevious: {},
                onNext: {},
                onSelectDate: { _ in }
            )
            SleepTimelineCanvas(
                night: night,
                viewportStart: night.detectedStart,
                viewportEnd: night.detectedEnd,
                selectedIntervalID: nil,
                onSelectInterval: { _ in },
                onUpdateViewport: { _, _ in }
            )
            .frame(height: 320)
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
    }
}
