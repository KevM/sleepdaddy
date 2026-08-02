import Testing
import SwiftUI
import UIKit
@testable import SleepDaddy

private final class DelayedEmptySleepStore: HealthKitSleepStoreProtocol, @unchecked Sendable {
    func requestAuthorization() async throws -> Bool {
        true
    }

    func fetchSleepSamples(start: Date, end: Date) async throws -> [NormalizedSleepInterval] {
        try await Task.sleep(for: .milliseconds(200))
        return []
    }
}

@MainActor
private final class HostedTimelinePresentationRecorder {
    var mode: SelectedNightLayoutMode?
    var timelineBounds: CGRect?
    var headerPresentation: NightHeaderView.Presentation?
    var headerBounds: CGRect?
    var landscapeToolbarIsPresent = false
    var landscapeToolbarElements: [LandscapeNightToolbarSemanticElement] = []
}

private struct TimelineLayoutModeCaptureView: UIViewRepresentable {
    let mode: SelectedNightLayoutMode?
    let recorder: HostedTimelinePresentationRecorder

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        recorder.mode = mode
    }
}

private struct TimelineBoundsCaptureView: View {
    let anchor: Anchor<CGRect>?
    let recorder: HostedTimelinePresentationRecorder

    var body: some View {
        GeometryReader { proxy in
            TimelineBoundsRecorderView(
                bounds: anchor.map { proxy[$0] },
                recorder: recorder
            )
            .frame(width: 0, height: 0)
        }
    }
}

private struct TimelineBoundsRecorderView: UIViewRepresentable {
    let bounds: CGRect?
    let recorder: HostedTimelinePresentationRecorder

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        recorder.timelineBounds = bounds
    }
}

private struct HeaderPresentationCaptureView: UIViewRepresentable {
    let presentation: NightHeaderView.Presentation?
    let recorder: HostedTimelinePresentationRecorder

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        recorder.headerPresentation = presentation
    }
}

private struct HeaderBoundsCaptureView: View {
    let anchor: Anchor<CGRect>?
    let recorder: HostedTimelinePresentationRecorder

    var body: some View {
        GeometryReader { proxy in
            HeaderBoundsRecorderView(
                bounds: anchor.map { proxy[$0] },
                recorder: recorder
            )
            .frame(width: 0, height: 0)
        }
    }
}

private struct HeaderBoundsRecorderView: UIViewRepresentable {
    let bounds: CGRect?
    let recorder: HostedTimelinePresentationRecorder

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        recorder.headerBounds = bounds
    }
}

private struct LandscapeToolbarPresenceCaptureView: UIViewRepresentable {
    let isPresent: Bool
    let recorder: HostedTimelinePresentationRecorder

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        recorder.landscapeToolbarIsPresent = isPresent
    }
}

private struct LandscapeToolbarElementsCaptureView: UIViewRepresentable {
    let elements: [LandscapeNightToolbarSemanticElement]
    let recorder: HostedTimelinePresentationRecorder

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        recorder.landscapeToolbarElements = elements
    }
}

private struct HostedTimelinePresentationMetrics {
    let mode: SelectedNightLayoutMode?
    let timelineBounds: CGRect?
    let headerPresentation: NightHeaderView.Presentation?
    let headerBounds: CGRect?
    let landscapeToolbarIsPresent: Bool
}

/// Composition tests for the timeline views.
///
/// These deliberately do *not* compare against reference PNGs. Pixel-exact baselines went
/// stale on every font, spacing, or OS change, and the only available response was to
/// re-record them — so a red test meant "re-record me", not "look at me", and stopped
/// carrying information. What is still worth asserting is that each composition assembles
/// its fixture, reaches the state the view expects, and rasterizes at its intended size.
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

    @Test @MainActor func landscapeToolbarSeparatesDateAndDuration() async throws {
        let locale = Locale(identifier: "en_US")
        let timeZone = TimeZone(secondsFromGMT: -12 * 3600)!
        let night = makeFixtureNight()
        let expectedDateLabel = NightHeaderView.formattedDate(
            night.date,
            locale: locale,
            timeZone: timeZone
        )
        let recorder = HostedTimelinePresentationRecorder()
        let toolbar = LandscapeNightToolbarView(
            night: night,
            dateRange: nil,
            onSelectDate: { _ in }
        )
        .environment(\.locale, locale)
        .environment(\.timeZone, timeZone)
        .overlayPreferenceValue(
            LandscapeNightToolbarSemanticElementsPreferenceKey.self
        ) { elements in
            LandscapeToolbarElementsCaptureView(
                elements: elements,
                recorder: recorder
            )
            .frame(width: 0, height: 0)
        }

        let controller = UIHostingController(rootView: toolbar)
        let windowScene = try #require(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        )
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 60)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        for _ in 0..<100 where recorder.landscapeToolbarElements.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        controller.view.layoutIfNeeded()

        let dateElement = try #require(
            recorder.landscapeToolbarElements.first { $0.role == .datePicker }
        )
        let durationElement = try #require(
            recorder.landscapeToolbarElements.first { $0.role == .duration }
        )
        #expect(recorder.landscapeToolbarElements.count == 2)
        #expect(dateElement.isInteractive)
        #expect(dateElement.accessibilityLabel == expectedDateLabel)
        #expect(dateElement.accessibilityHint == "Double tap to choose a date.")
        #expect(!dateElement.accessibilityLabel.contains("4h 30m"))
        #expect(!durationElement.isInteractive)
        #expect(durationElement.accessibilityLabel == "Sleep duration, 4h 30m")
        #expect(durationElement.accessibilityHint == nil)
        try await Task.sleep(for: .milliseconds(50))
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(10))
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

    /// Hosts `view` in a real window so `@State`-driven content settles before rendering.
    ///
    /// `ImageRenderer` alone rasterizes a view that never entered a window, which is not
    /// enough for compositions that load asynchronously.
    @MainActor
    @discardableResult
    private func assertHostedComposition(
        of view: some View,
        named name: String,
        width: CGFloat,
        height: CGFloat,
        expectedTimelineLayoutMode: SelectedNightLayoutMode? = nil,
        expectsLandscapeToolbar: Bool = false,
        isReady: @escaping @MainActor () -> Bool
    ) async throws -> HostedTimelinePresentationMetrics {
        let size = CGSize(width: width, height: height)
        let recorder = HostedTimelinePresentationRecorder()
        let controller = UIHostingController(
            rootView: view.overlayPreferenceValue(
                SelectedNightTimelineLayoutPreferenceKey.self
            ) { layoutMode in
                TimelineLayoutModeCaptureView(
                    mode: layoutMode,
                    recorder: recorder
                )
                .frame(width: 0, height: 0)
            }
            .overlayPreferenceValue(
                SelectedNightTimelineBoundsPreferenceKey.self
            ) { anchor in
                TimelineBoundsCaptureView(anchor: anchor, recorder: recorder)
            }
            .overlayPreferenceValue(
                NightHeaderPresentationPreferenceKey.self
            ) { presentation in
                HeaderPresentationCaptureView(
                    presentation: presentation,
                    recorder: recorder
                )
                .frame(width: 0, height: 0)
            }
            .overlayPreferenceValue(
                NightHeaderBoundsPreferenceKey.self
            ) { anchor in
                HeaderBoundsCaptureView(anchor: anchor, recorder: recorder)
            }
            .overlayPreferenceValue(
                LandscapeNightToolbarPresencePreferenceKey.self
            ) { isPresent in
                LandscapeToolbarPresenceCaptureView(
                    isPresent: isPresent,
                    recorder: recorder
                )
                .frame(width: 0, height: 0)
            }
        )
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            Issue.record("Failed to find a window scene for hosted composition \(name)")
            return HostedTimelinePresentationMetrics(
                mode: nil,
                timelineBounds: nil,
                headerPresentation: nil,
                headerBounds: nil,
                landscapeToolbarIsPresent: false
            )
        }
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.isHidden = false

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let hostedContentIsReady = {
            isReady()
                && (expectedTimelineLayoutMode == nil
                    || recorder.mode == expectedTimelineLayoutMode)
                && (!expectsLandscapeToolbar || recorder.landscapeToolbarIsPresent)
        }
        for _ in 0..<200 where !hostedContentIsReady() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            hostedContentIsReady(),
            "\(name): Hosted content did not reach its expected state"
        )
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        if let expectedTimelineLayoutMode {
            #expect(
                recorder.mode == expectedTimelineLayoutMode,
                "\(name): Expected timeline layout \(expectedTimelineLayoutMode), got \(String(describing: recorder.mode))"
            )
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let currentImage = renderer.image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(10))

        guard let cgImage = currentImage.cgImage else {
            Issue.record("Failed to render hosted composition \(name)")
            return HostedTimelinePresentationMetrics(
                mode: recorder.mode,
                timelineBounds: recorder.timelineBounds,
                headerPresentation: recorder.headerPresentation,
                headerBounds: recorder.headerBounds,
                landscapeToolbarIsPresent: recorder.landscapeToolbarIsPresent
            )
        }

        #expect(cgImage.width == Int(width * 2.0), "\(name) width")
        #expect(cgImage.height == Int(height * 2.0), "\(name) height")

        return HostedTimelinePresentationMetrics(
            mode: recorder.mode,
            timelineBounds: recorder.timelineBounds,
            headerPresentation: recorder.headerPresentation,
            headerBounds: recorder.headerBounds,
            landscapeToolbarIsPresent: recorder.landscapeToolbarIsPresent
        )
    }

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

    @Test @MainActor func testSnapshotEmptyLoadedNight() async throws {
        var fixtureCalendar = Calendar(identifier: .gregorian)
        fixtureCalendar.timeZone = .current
        let now = fixtureCalendar.date(
            from: DateComponents(year: 2026, month: 7, day: 25, hour: 12)
        )!
        let testDefaults = UserDefaults(suiteName: "SnapshotTests.EmptyLoadedNight")!
        testDefaults.removePersistentDomain(forName: "SnapshotTests.EmptyLoadedNight")
        let model = NightBrowserModel(
            store: DelayedEmptySleepStore(),
            preferencesStore: PreferencesStore(userDefaults: testDefaults),
            now: { now }
        )
        await model.loadData()

        #expect(model.appState == .loaded)
        #expect(model.selectedAssembledNight?.hasSleepData == false)
        let selectedDate = fixtureCalendar.dateComponents(
            [.year, .month, .day],
            from: model.selectedDate
        )
        #expect(selectedDate == DateComponents(year: 2026, month: 7, day: 24))

        let content = ContentView(model: model)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        try await assertHostedComposition(
            of: content,
            named: "empty loaded night",
            width: 393,
            height: 520,
            isReady: { model.appState == .loaded }
        )
    }

    @Test @MainActor func loadedLandscapeKeepsImmersiveTimeline() async throws {
        let model = await makeLoadedFixtureModel(suiteName: "SnapshotTests.LoadedLandscape")
        let content = ContentView(model: model)
            .environment(\.verticalSizeClass, .compact)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let metrics = try await assertHostedComposition(
            of: content,
            named: "loaded landscape",
            width: 852,
            height: 393,
            expectedTimelineLayoutMode: .immersiveLandscape,
            expectsLandscapeToolbar: true,
            isReady: { model.appState == .loaded }
        )
        let timelineBounds = try #require(metrics.timelineBounds)
        #expect(
            timelineBounds.height >= 220,
            "Actual post-frame timeline bounds: \(timelineBounds)"
        )
        #expect(metrics.landscapeToolbarIsPresent)
        #expect(metrics.headerPresentation == nil)
    }

    @Test @MainActor func loadedLandscapeAccessibilityKeepsImmersiveTimeline() async throws {
        let model = await makeLoadedFixtureModel(suiteName: "SnapshotTests.LoadedLandscapeAccessibility")
        let content = ContentView(model: model)
            .environment(\.verticalSizeClass, .compact)
            .environment(\.dynamicTypeSize, .accessibility2)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let metrics = try await assertHostedComposition(
            of: content,
            named: "loaded landscape accessibility",
            width: 852,
            height: 393,
            expectedTimelineLayoutMode: .immersiveLandscape,
            expectsLandscapeToolbar: true,
            isReady: { model.appState == .loaded }
        )
        let timelineBounds = try #require(metrics.timelineBounds)
        #expect(
            timelineBounds.height >= 220,
            "Actual post-frame timeline bounds: \(timelineBounds)"
        )
        #expect(metrics.landscapeToolbarIsPresent)
        #expect(metrics.headerPresentation == nil)
    }

    @Test @MainActor func loadedPortraitUsesStandardComposition() async throws {
        let model = await makeLoadedFixtureModel(suiteName: "SnapshotTests.LoadedPortrait")
        let content = ContentView(model: model)
            .environment(\.verticalSizeClass, .regular)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let metrics = try await assertHostedComposition(
            of: content,
            named: "loaded portrait",
            width: 393,
            height: 852,
            expectedTimelineLayoutMode: .standard,
            isReady: { model.appState == .loaded }
        )
        #expect(metrics.headerPresentation == .standalone)
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

    @Test @MainActor func immersiveEmptyNightUsesEdgeNavigation() async throws {
        var fixtureCalendar = Calendar(identifier: .gregorian)
        fixtureCalendar.timeZone = .current
        let now = fixtureCalendar.date(
            from: DateComponents(year: 2026, month: 7, day: 25, hour: 12)
        )!
        let suiteName = "SnapshotTests.ImmersiveEmptyNight"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        let model = NightBrowserModel(
            store: DelayedEmptySleepStore(),
            preferencesStore: PreferencesStore(userDefaults: testDefaults),
            now: { now }
        )
        await model.loadData()

        let content = ContentView(model: model)
            .environment(\.verticalSizeClass, .compact)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        let metrics = try await assertHostedComposition(
            of: content,
            named: "immersive empty night",
            width: 852,
            height: 393,
            expectsLandscapeToolbar: true,
            isReady: { model.appState == .loaded }
        )

        #expect(metrics.landscapeToolbarIsPresent)
        #expect(metrics.headerPresentation == nil)
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
            SlimContextNavigator(
                night: night,
                viewportStart: night.detectedStart,
                viewportEnd: night.detectedEnd,
                onUpdateViewport: { _ in }
            )
        }
        .padding(16)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
