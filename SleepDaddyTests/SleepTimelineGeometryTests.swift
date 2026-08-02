import Testing
import Foundation
import CoreGraphics
@testable import SleepDaddy

struct SleepTimelineGeometryTests {
    @Test func leadingEdgeLabelCullsTheInteriorLabelItWouldOverlap() {
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

        let layouts = geometry.timeLabelLayouts(for: [
            TimelineTimeLabelCandidate(index: 0, tickX: 0, labelWidth: 80),
            TimelineTimeLabelCandidate(index: 1, tickX: 65, labelWidth: 40),
            TimelineTimeLabelCandidate(index: 2, tickX: 200, labelWidth: 40)
        ])

        #expect(layouts.map(\.candidateIndex) == [0, 2])
        #expect(layouts.map(\.centerX) == [40, 200])
    }

    @Test func trailingEdgeLabelCullsTheInteriorLabelItWouldOverlap() {
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

        let layouts = geometry.timeLabelLayouts(for: [
            TimelineTimeLabelCandidate(index: 0, tickX: 200, labelWidth: 40),
            TimelineTimeLabelCandidate(index: 1, tickX: 335, labelWidth: 40),
            TimelineTimeLabelCandidate(index: 2, tickX: 400, labelWidth: 80)
        ])

        #expect(layouts.map(\.candidateIndex) == [0, 2])
        #expect(layouts.map(\.centerX) == [200, 360])
    }

    @Test func nonOverlappingInteriorTimeLabelsStayCenteredOnTheirTicks() {
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

        let layouts = geometry.timeLabelLayouts(for: [
            TimelineTimeLabelCandidate(index: 0, tickX: 100, labelWidth: 40),
            TimelineTimeLabelCandidate(index: 1, tickX: 200, labelWidth: 60),
            TimelineTimeLabelCandidate(index: 2, tickX: 300, labelWidth: 40)
        ])

        #expect(layouts.map(\.candidateIndex) == [0, 1, 2])
        #expect(layouts.map(\.centerX) == [100, 200, 300])
    }

    @Test func abuttingTimeLabelsAreCulledSoTheyDoNotReadAsOneWord() {
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

        // Bounds touch exactly at x = 120 without intersecting, which renders as
        // "11:00 PM1:00 AM" — legible only if a gap is required between labels.
        let layouts = geometry.timeLabelLayouts(for: [
            TimelineTimeLabelCandidate(index: 0, tickX: 100, labelWidth: 40),
            TimelineTimeLabelCandidate(index: 1, tickX: 140, labelWidth: 40)
        ])

        #expect(layouts.map(\.candidateIndex) == [0])
    }

    @Test func timeLabelsSeparatedByTheMinimumGapAreBothKept() {
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

        let gap = TimelineTimeLabelLayout.minimumGap
        let layouts = geometry.timeLabelLayouts(for: [
            TimelineTimeLabelCandidate(index: 0, tickX: 100, labelWidth: 40),
            TimelineTimeLabelCandidate(index: 1, tickX: 140 + gap, labelWidth: 40)
        ])

        #expect(layouts.map(\.candidateIndex) == [0, 1])
    }

    @Test func timeLabelsWiderThanCanvasAreCulled() {
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

        let layouts = geometry.timeLabelLayouts(for: [
            TimelineTimeLabelCandidate(index: 0, tickX: 0, labelWidth: 80),
            TimelineTimeLabelCandidate(index: 1, tickX: 40, labelWidth: 20)
        ])

        #expect(layouts.map(\.candidateIndex) == [1])
        #expect(layouts[0].centerX == 40)
    }

    @Test func testCoordinateConversion() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let end = now.addingTimeInterval(3600) // 1 hour

        let geom = SleepTimelineGeometry(
            totalStart: now,
            totalEnd: end,
            viewport: TimelineViewport(start: now, end: end),
            canvasWidth: 360.0,
            canvasHeight: 300.0
        )

        #expect(geom.xPosition(for: now) == 7.0)
        #expect(geom.xPosition(for: end) == 353.0)
        #expect(geom.xPosition(for: now.addingTimeInterval(1800)) == 180.0)

        #expect(geom.date(atX: 0.0) == now)
        #expect(geom.date(atX: 360.0) == end)
    }

    @Test func testViewportPinchZoomClamping() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let viewport = TimelineViewport(start: start, end: end)

        let geom = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 300.0,
            canvasHeight: 300.0
        )

        let zoomed = geom.zoomed(viewport, magnification: 2.0, anchorX: 150.0)

        // Zooming in by 2.0 cuts duration in half (from 12h to 6h)
        #expect(zoomed.duration == 6 * 3600)
        #expect(zoomed.start >= start)
        #expect(zoomed.end <= end)
    }

    @Test func testHitTestInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let end = now.addingTimeInterval(3600)

        let geom = SleepTimelineGeometry(
            totalStart: now,
            totalEnd: end,
            viewport: TimelineViewport(start: now, end: end),
            canvasWidth: 360.0,
            canvasHeight: 300.0
        )

        let item = NormalizedSleepInterval(
            id: "hit-me",
            startDate: now.addingTimeInterval(900),
            endDate: now.addingTimeInterval(1800),
            stage: .rem,
            sourceName: "Watch",
            sourceIdentifier: "watch"
        )

        let rect = geom.rect(for: item)
        let midPoint = CGPoint(x: rect.midX, y: rect.midY)

        let found = geom.intervalAt(point: midPoint, in: [item])
        #expect(found?.id == "hit-me")

        let missPoint = CGPoint(x: 10, y: 10)
        let miss = geom.intervalAt(point: missPoint, in: [item])
        #expect(miss == nil)
    }

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

        #expect(abs(rect.minX - 103.5) < 0.001)
        #expect(abs(rect.maxX - 200) < 0.001)
        #expect(abs(rect.minY - 88) < 0.001)
        #expect(abs(rect.maxY - 244) < 0.001)
    }

    @Test func unspecifiedSleepUsesCenterOfSleepRowsForConnectors() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 360,
            canvasHeight: 300
        )
        let core = NormalizedSleepInterval(
            id: "core",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            stage: .core,
            sourceName: "Fixture",
            sourceIdentifier: "fixture"
        )
        let unspecified = NormalizedSleepInterval(
            id: "unspecified",
            startDate: start.addingTimeInterval(3600),
            endDate: start.addingTimeInterval(2 * 3600),
            stage: .asleepUnspecified,
            sourceName: "Fixture",
            sourceIdentifier: "fixture"
        )
        let rem = NormalizedSleepInterval(
            id: "rem",
            startDate: start.addingTimeInterval(2 * 3600),
            endDate: start.addingTimeInterval(3 * 3600),
            stage: .rem,
            sourceName: "Fixture",
            sourceIdentifier: "fixture"
        )

        let connectors = geometry.stepSegments(for: [core, unspecified, rem])
            .filter(\.isConnector)

        #expect(connectors.count == 2)
        #expect(connectors[0].start == CGPoint(x: 35.83333333333333, y: 166))
        #expect(connectors[0].end == CGPoint(x: 35.83333333333333, y: 166))
        #expect(connectors[1].start == CGPoint(x: 64.66666666666666, y: 166))
        #expect(connectors[1].end == CGPoint(x: 64.66666666666666, y: 106))
    }

    @Test func unspecifiedSleepCanBeHitAnywhereInsideSpanningBand() {
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

        let found = geometry.intervalAt(
            point: CGPoint(x: 150, y: 240),
            in: [interval]
        )

        #expect(found?.id == "unspecified")
    }

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
        #expect(geometry.clamped(zoomed) == zoomed)
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
        #expect(abs(clampedSmall.midpoint.timeIntervalSince(tooSmall.midpoint)) < 0.001)
        #expect(geometry.clamped(clampedSmall) == clampedSmall)

        let tooLarge = TimelineViewport(start: start.addingTimeInterval(-3600),
                                        end: end.addingTimeInterval(3600))
        #expect(geometry.clamped(tooLarge) == TimelineViewport(start: start, end: end))
    }

    @Test func panPreservesDurationAndStaysInsideNight() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let viewport = TimelineViewport(start: start.addingTimeInterval(3600),
                                        end: start.addingTimeInterval(3 * 3600))
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 400,
            canvasHeight: 300
        )

        // Panning scales against the inset plot width, not the clipped canvas edges.
        let panned = geometry.panned(viewport, deltaX: -100)
        #expect(abs(panned.duration - viewport.duration) < 0.001)
        #expect(abs(panned.start.timeIntervalSince(viewport.start) - 1_865.2849740932643) < 0.001)
        #expect(geometry.clamped(panned) == panned)

        // Panning past the start of the night clamps without shrinking the viewport.
        let pinned = geometry.panned(viewport, deltaX: 4000)
        #expect(pinned == TimelineViewport(start: start, end: start.addingTimeInterval(2 * 3600)))
    }

    @Test func fullNightBoundaryPositionsLeaveRoomForRoundedStrokeCaps() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(8 * 3600)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 400,
            canvasHeight: 300
        )

        #expect(geometry.xPosition(for: start) >= 7)
        #expect(geometry.xPosition(for: end) <= 393)
    }

    @Test func normalizingInitWidensDegenerateAndInvertedRanges() {
        let start = Date(timeIntervalSinceReferenceDate: 0)

        let degenerate = TimelineViewport(normalizing: start, end: start)
        #expect(degenerate.start == start)
        #expect(degenerate.duration == 1)

        let inverted = TimelineViewport(normalizing: start.addingTimeInterval(600), end: start)
        #expect(inverted.start == start.addingTimeInterval(600))
        #expect(inverted.duration == 1)

        // A valid range is passed through untouched.
        let valid = TimelineViewport(normalizing: start, end: start.addingTimeInterval(3600))
        #expect(valid == TimelineViewport(start: start, end: start.addingTimeInterval(3600)))
    }

    @Test func clampNeverExceedsNightsShorterThanTheMinimumWindow() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(60) // Shorter than the 300s minimum window.
        let viewport = TimelineViewport(start: start, end: end)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 400,
            canvasHeight: 300
        )

        let clamped = geometry.clamped(TimelineViewport(start: start, end: start.addingTimeInterval(5)))
        #expect(clamped == viewport)

        let zoomed = geometry.zoomed(viewport, magnification: 8, anchorX: 200)
        #expect(zoomed == viewport)
    }

    @Test func gesturesToleratePathologicalInputs() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let viewport = TimelineViewport(start: start, end: end)

        // A zero-width canvas must not divide by zero or produce NaN dates.
        let collapsed = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 0,
            canvasHeight: 300
        )
        #expect(collapsed.xPosition(for: end) == 0)
        #expect(collapsed.date(atX: 50) == start)
        #expect(collapsed.zoomed(viewport, magnification: 2, anchorX: 0).duration == 6 * 3600)
        #expect(collapsed.panned(viewport, deltaX: 10) == viewport)

        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 400,
            canvasHeight: 300
        )

        // An anchor outside the canvas behaves as an anchor pinned to the nearest edge.
        let belowZero = geometry.zoomed(viewport, magnification: 2, anchorX: -100)
        #expect(belowZero == geometry.zoomed(viewport, magnification: 2, anchorX: 0))
        let aboveWidth = geometry.zoomed(viewport, magnification: 2, anchorX: 900)
        #expect(aboveWidth == geometry.zoomed(viewport, magnification: 2, anchorX: 400))

        // Zero or negative magnification widens rather than dividing by zero.
        #expect(geometry.zoomed(viewport, magnification: 0, anchorX: 200) == viewport)
        #expect(geometry.zoomed(viewport, magnification: -2, anchorX: 200) == viewport)
    }

    @Test func consecutiveStagesProduceHorizontalSegmentsAndConnector() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 360.0,
            canvasHeight: 300.0
        )

        let first = NormalizedSleepInterval(
            id: "core",
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "watch"
        )
        let second = NormalizedSleepInterval(
            id: "deep",
            startDate: start.addingTimeInterval(1800),
            endDate: start.addingTimeInterval(3600),
            stage: .deep,
            sourceName: "Watch",
            sourceIdentifier: "watch"
        )

        let segments = geometry.stepSegments(for: [first, second])

        #expect(segments.filter(\.isConnector).count == 1)
        #expect(segments.count == 3)
        #expect(segments[0].end.x == segments[1].start.x)
        #expect(segments[1].end.y == segments[2].start.y)
    }

    @Test func twelveHourViewportUsesSparseTicks() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 360.0,
            canvasHeight: 300.0
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let ticks = geometry.timeTicks(calendar: calendar)
        #expect(ticks.count >= 4)
        #expect(ticks.count <= 7)
        #expect(ticks.allSatisfy { calendar.component(.minute, from: $0.date) == 0 })
    }

    @Test func thirtyMinuteViewportUsesFiveMinuteTicks() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 360.0,
            canvasHeight: 300.0
        )

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let zoomed = geometry.replacingViewport(
            TimelineViewport(start: start, end: start.addingTimeInterval(1800))
        )
        let ticks = zoomed.timeTicks(calendar: calendar)
        let deltas = zip(ticks, ticks.dropFirst()).map {
            $1.date.timeIntervalSince($0.date)
        }
        #expect(deltas.allSatisfy { abs($0 - 300) < 0.001 })
    }

    @Test func navigatorDragMovesViewportByFullNightRatio() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let viewport = TimelineViewport(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5 * 3600))
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 400,
            canvasHeight: 300
        )

        let moved = geometry.navigatorViewport(
            viewport,
            translatedBy: 40,
            navigatorWidth: 400
        )
        #expect(abs(moved.start.timeIntervalSince(viewport.start) - 4_320) < 0.001)
    }

    @Test func navigatorTapRecentersWithoutChangingDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let viewport = TimelineViewport(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(5 * 3600))
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: viewport,
            canvasWidth: 400,
            canvasHeight: 300
        )

        let moved = geometry.navigatorViewport(
            viewport,
            centeredAtX: 300,
            navigatorWidth: 400
        )
        #expect(moved.duration == viewport.duration)
        #expect(geometry.clamped(moved) == moved)
    }

    @Test func timelineCanvasReservesCombinedRailHeightExactlyOnce() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(12 * 3600)
        let layout = SleepTimelineCanvasVerticalLayout(totalHeight: 320)
        let geometry = SleepTimelineGeometry(
            totalStart: start,
            totalEnd: end,
            viewport: TimelineViewport(start: start, end: end),
            canvasWidth: 400,
            canvasHeight: layout.geometryHeight
        )

        #expect(layout.plotHeight == 276)
        #expect(geometry.usablePlotHeight() == 260)
        #expect(layout.plotHeight - geometry.usablePlotHeight() == SleepTimelineGeometry.topPadding)
    }

    @Test func combinedTimelineRailUsesOneCompactTouchTarget() {
        #expect(SleepTimelineGeometry.timeAxisHeight == 44)
        #expect(SleepTimelineGeometry.timeLabelBandHeight == 20)
        #expect(SleepTimelineGeometry.navigatorTrackHeight == 10)
    }
}
