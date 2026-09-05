import Testing
import Foundation
import CoreGraphics
@testable import SleepDaddy

/// The viewport is 500…1500s wide on a 1014pt canvas, so after the 7pt plot inset one
/// second is exactly one point: t=500 lands at x=7 and t=1500 at x=1007. Every expected
/// value below is read off that mapping.
struct StageBackgroundSpansTests {
    // MARK: - Fixtures

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private func interval(
        _ start: TimeInterval,
        _ end: TimeInterval,
        _ stage: SleepStage,
        source: String = "watch"
    ) -> NormalizedSleepInterval {
        NormalizedSleepInterval(
            id: "\(stage.rawValue)-\(start)-\(source)",
            startDate: date(start),
            endDate: date(end),
            stage: stage,
            sourceName: source,
            sourceIdentifier: source
        )
    }

    private func geometry() -> SleepTimelineGeometry {
        SleepTimelineGeometry(
            totalStart: date(0),
            totalEnd: date(2_000),
            viewport: TimelineViewport(normalizing: date(500), end: date(1_500)),
            canvasWidth: 1_014,
            canvasHeight: 100
        )
    }

    private func isClose(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) < 0.001
    }

    // MARK: - Which intervals get a wash

    /// `stepSegments` drops `.inBed` before drawing the stage plot. The wash has to drop it
    /// too, or the background asserts a band where the plot above shows nothing.
    @Test func inBedIntervalsProduceNoSpan() {
        let spans = StageBackgroundSpans(
            intervals: [interval(600, 700, .inBed)],
            geometry: geometry()
        )
        #expect(spans.spans.isEmpty)
    }

    @Test func aSleepStageProducesOneSpan() {
        let spans = StageBackgroundSpans(
            intervals: [interval(600, 700, .rem)],
            geometry: geometry()
        )
        #expect(spans.spans.count == 1)
        #expect(spans.spans.first?.stage == .rem)
        #expect(isClose(spans.spans[0].startX, 107))
        #expect(isClose(spans.spans[0].endX, 207))
    }

    // MARK: - Clipping to the viewport

    @Test func aSpanStartingBeforeTheViewportClipsToTheLeadingPlotEdge() {
        let spans = StageBackgroundSpans(
            intervals: [interval(400, 700, .core)],
            geometry: geometry()
        )
        #expect(spans.spans.count == 1)
        #expect(isClose(spans.spans[0].startX, 7))
        #expect(isClose(spans.spans[0].endX, 207))
    }

    @Test func aSpanEndingAfterTheViewportClipsToTheTrailingPlotEdge() {
        let spans = StageBackgroundSpans(
            intervals: [interval(1_400, 1_600, .core)],
            geometry: geometry()
        )
        #expect(spans.spans.count == 1)
        #expect(isClose(spans.spans[0].startX, 907))
        #expect(isClose(spans.spans[0].endX, 1_007))
    }

    @Test func intervalsEntirelyOutsideTheViewportProduceNoSpan() {
        let spans = StageBackgroundSpans(
            intervals: [interval(100, 200, .core), interval(1_800, 1_900, .deep)],
            geometry: geometry()
        )
        #expect(spans.spans.isEmpty)
    }

    /// At a wide zoom a short interval collapses below a point. Drawing it would put a
    /// hairline of stage colour under the lane that reads as noise rather than as a stage.
    @Test func subPixelSpansAreDropped() {
        let spans = StageBackgroundSpans(
            intervals: [interval(600, 600.2, .awake)],
            geometry: geometry()
        )
        #expect(spans.spans.isEmpty)
    }

    // MARK: - Transition rules

    @Test func abuttingStagesProduceATransitionRuleAtTheBoundary() {
        let spans = StageBackgroundSpans(
            intervals: [interval(600, 700, .core), interval(700, 800, .rem)],
            geometry: geometry()
        )
        #expect(spans.transitions.count == 1)
        #expect(isClose(spans.transitions[0], 207))
    }

    @Test func aGapBetweenStagesProducesNoTransitionRule() {
        let spans = StageBackgroundSpans(
            intervals: [interval(600, 700, .core), interval(800, 900, .rem)],
            geometry: geometry()
        )
        #expect(spans.transitions.isEmpty)
    }

    /// Filtering `.inBed` leaves its neighbours no longer touching, so they must not be
    /// joined by a rule that claims a transition the sleeper never made.
    @Test func aFilteredInBedIntervalDoesNotJoinItsNeighbours() {
        let spans = StageBackgroundSpans(
            intervals: [
                interval(600, 700, .core),
                interval(700, 800, .inBed),
                interval(800, 900, .rem),
            ],
            geometry: geometry()
        )
        #expect(spans.spans.count == 2)
        #expect(spans.transitions.isEmpty)
    }

    /// The assembler coalesces only when stage *and* source match, so one stage can arrive
    /// as two touching intervals from two sources. That is not a transition.
    @Test func abuttingIntervalsOfTheSameStageProduceNoTransitionRule() {
        let spans = StageBackgroundSpans(
            intervals: [
                interval(600, 700, .core, source: "watch"),
                interval(700, 800, .core, source: "phone"),
            ],
            geometry: geometry()
        )
        #expect(spans.transitions.isEmpty)
    }

    @Test func aLoneSpanHasNoLeadingTransitionRule() {
        let spans = StageBackgroundSpans(
            intervals: [interval(600, 700, .core)],
            geometry: geometry()
        )
        #expect(spans.transitions.isEmpty)
    }

    // MARK: - Legend

    /// The legend names what the wash paints, so it is derived from the same rule rather
    /// than a parallel list that could drift out of agreement with it.
    @Test func theLegendExcludesInBedJustAsTheWashDoes() {
        let stages = StageBackgroundSpans.legendStages(in: [
            interval(600, 700, .core),
            interval(700, 800, .inBed),
        ])
        #expect(stages == [.core])
    }

    @Test func theLegendListsStagesInTimelineRowOrder() {
        let stages = StageBackgroundSpans.legendStages(in: [
            interval(600, 700, .deep),
            interval(700, 800, .awake),
            interval(800, 900, .core),
            interval(900, 1_000, .rem),
        ])
        #expect(stages == [.awake, .rem, .core, .deep])
    }

    /// A stage recurs many times across a night; it earns one chip, not one per interval.
    @Test func theLegendNamesEachStageOnce() {
        let stages = StageBackgroundSpans.legendStages(in: [
            interval(600, 700, .core),
            interval(700, 800, .rem),
            interval(800, 900, .core),
            interval(900, 1_000, .core),
        ])
        #expect(stages == [.rem, .core])
    }

    @Test func theLegendIsEmptyWhenNothingIsWashed() {
        #expect(StageBackgroundSpans.legendStages(in: []).isEmpty)
        #expect(StageBackgroundSpans.legendStages(in: [interval(600, 700, .inBed)]).isEmpty)
    }

    @Test func anEmptyNightProducesNothingToDraw() {
        let spans = StageBackgroundSpans(intervals: [], geometry: geometry())
        #expect(spans.spans.isEmpty)
        #expect(spans.transitions.isEmpty)
    }
}
