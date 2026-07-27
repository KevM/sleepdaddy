import Testing
import Foundation
import CoreGraphics
@testable import SleepDaddy

/// A 12-hour night on a 400x300 canvas, so one canvas pixel is 108 seconds of the full night.
private struct InteractionFixture {
    let totalStart = Date(timeIntervalSinceReferenceDate: 0)

    var totalEnd: Date { totalStart.addingTimeInterval(12 * 3600) }

    /// The whole night: already pinned against both bounds, so any pan is pure overscroll.
    var fullViewport: TimelineViewport {
        TimelineViewport(start: totalStart, end: totalEnd)
    }

    /// A strictly interior two-hour window, far enough from both bounds that a
    /// settled pan or fling lands without being clamped.
    var middleViewport: TimelineViewport {
        TimelineViewport(start: totalStart.addingTimeInterval(5 * 3600),
                         end: totalStart.addingTimeInterval(7 * 3600))
    }

    var geometry: SleepTimelineGeometry {
        SleepTimelineGeometry(
            totalStart: totalStart,
            totalEnd: totalEnd,
            viewport: fullViewport,
            canvasWidth: 400,
            canvasHeight: 300
        )
    }
}

struct TimelineInteractionControllerTests {
    @Test func repeatedMagnificationUsesGestureBaseline() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.fullViewport)
        controller.begin(viewport: fixture.fullViewport)

        controller.updateMagnification(1.5, anchorX: 200, geometry: fixture.geometry)
        controller.updateMagnification(2.0, anchorX: 200, geometry: fixture.geometry)

        #expect(abs(controller.liveViewport.duration - 6 * 3600) < 0.001)
    }

    @Test func repeatedPanUsesGestureBaseline() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.middleViewport)
        controller.begin(viewport: fixture.middleViewport)

        // Recognizers report cumulative translation, so the second call replaces the first.
        controller.updatePan(translationX: -20, geometry: fixture.geometry)
        controller.updatePan(translationX: -40, geometry: fixture.geometry)

        #expect(controller.liveViewport == fixture.geometry.panned(fixture.middleViewport, deltaX: -40))
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

    @Test func edgeResistanceDampsOverscrollAtTheStartOfTheNight() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.fullViewport)
        controller.begin(viewport: fixture.fullViewport)

        // The window already covers the night, so all 200pt of this drag is overscroll.
        controller.updatePan(translationX: 200, geometry: fixture.geometry)
        let nudged = controller.liveViewport
        let nudgedOffset = fixture.totalStart.timeIntervalSince(nudged.start)
        let rawShift = 0.5 * fixture.fullViewport.duration

        #expect(nudgedOffset > 0)
        #expect(nudgedOffset < rawShift)
        #expect(abs(nudged.duration - fixture.fullViewport.duration) < 0.001)

        // A wild drag keeps pulling in the same direction but never past the resistance limit.
        controller.updatePan(translationX: 100_000, geometry: fixture.geometry)
        let flung = controller.liveViewport
        let flungOffset = fixture.totalStart.timeIntervalSince(flung.start)

        #expect(flungOffset > nudgedOffset)
        #expect(flungOffset < TimelineInteractionController.overscrollLimitFraction
                * fixture.fullViewport.duration)
    }

    @Test func edgeResistanceDampsOverscrollAtTheEndOfTheNight() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.fullViewport)
        controller.begin(viewport: fixture.fullViewport)

        // Mirror of the start-of-night case: dragging left pushes past `totalEnd` instead.
        controller.updatePan(translationX: -200, geometry: fixture.geometry)
        let nudged = controller.liveViewport
        let nudgedOffset = nudged.end.timeIntervalSince(fixture.totalEnd)
        let rawShift = 0.5 * fixture.fullViewport.duration

        #expect(nudgedOffset > 0)
        #expect(nudgedOffset < rawShift)
        #expect(abs(nudged.duration - fixture.fullViewport.duration) < 0.001)

        controller.updatePan(translationX: -100_000, geometry: fixture.geometry)
        let flung = controller.liveViewport
        let flungOffset = flung.end.timeIntervalSince(fixture.totalEnd)

        #expect(flung.end > fixture.totalEnd)
        #expect(flungOffset > nudgedOffset)
        #expect(flungOffset < TimelineInteractionController.overscrollLimitFraction
                * fixture.fullViewport.duration)
    }

    @Test func overPinchIsClampedRatherThanRubberBanded() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.fullViewport)
        controller.begin(viewport: fixture.fullViewport)

        // Zooming out from the whole night has nowhere to go. Unlike a pan, it gets no
        // give at all: a window that sprang back in size would read as a glitch.
        controller.updateMagnification(0.25, anchorX: 200, geometry: fixture.geometry)
        #expect(controller.liveViewport == fixture.fullViewport)

        // And it stays put no matter how hard it is pushed — no progressive overshoot.
        controller.updateMagnification(0.001, anchorX: 200, geometry: fixture.geometry)
        #expect(controller.liveViewport == fixture.fullViewport)
    }

    @Test func settlingDiscardsOverscroll() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.fullViewport)
        controller.begin(viewport: fixture.fullViewport)
        controller.updatePan(translationX: 200, geometry: fixture.geometry)
        #expect(controller.liveViewport != fixture.fullViewport)

        let settled = controller.settledViewport(
            geometry: fixture.geometry,
            velocityX: 0,
            reduceMotion: false
        )

        #expect(settled == fixture.fullViewport)
        #expect(controller.liveViewport == fixture.fullViewport)
    }

    @Test func inertiaFollowsVelocityDirectionAndIsCapped() {
        let fixture = InteractionFixture()

        func settle(_ velocityX: CGFloat) -> TimelineViewport {
            var controller = TimelineInteractionController(viewport: fixture.middleViewport)
            controller.begin(viewport: fixture.middleViewport)
            return controller.settledViewport(
                geometry: fixture.geometry,
                velocityX: velocityX,
                reduceMotion: false
            )
        }

        let resting = settle(0)
        #expect(resting == fixture.middleViewport)

        // Velocity follows the pan convention: leftward (negative) travel moves later in time.
        #expect(settle(-300).start > resting.start)
        #expect(settle(300).start < resting.start)

        // The projection is capped, so an absurd velocity lands where a merely large one does...
        #expect(settle(-5_000) == settle(-50_000))
        // ...and that landing is inside the night, proving the cap bound it rather than clamping.
        #expect(settle(-50_000).end < fixture.totalEnd)
    }

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

    @Test func cancelDiscardsInFlightGesture() {
        let fixture = InteractionFixture()
        var controller = TimelineInteractionController(viewport: fixture.fullViewport)
        controller.begin(viewport: fixture.fullViewport)
        controller.updateMagnification(4, anchorX: 200, geometry: fixture.geometry)
        controller.updatePan(translationX: -120, geometry: fixture.geometry)

        controller.cancel(viewport: fixture.middleViewport)
        #expect(controller.liveViewport == fixture.middleViewport)

        // The next gesture builds on the cancelled-to viewport, with no leftover zoom or pan.
        controller.updatePan(translationX: -40, geometry: fixture.geometry)
        #expect(controller.liveViewport == fixture.geometry.panned(fixture.middleViewport, deltaX: -40))
    }
}
