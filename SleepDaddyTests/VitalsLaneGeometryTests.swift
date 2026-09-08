import Testing
import Foundation
import CoreGraphics
@testable import SleepDaddy

struct VitalsLaneGeometryTests {
    @Test func theMaximumSitsAtTheTopAndTheMinimumAtTheBottom() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 100)
        #expect(geometry.yPosition(for: 100.0) == 0)
        #expect(geometry.yPosition(for: 70.0) == 100)
    }

    @Test func themidpointLandsHalfway() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 100)
        #expect(geometry.yPosition(for: 85.0) == 50)
    }

    @Test func valuesBeyondTheRangeClampToTheLaneEdges() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 100)
        #expect(geometry.yPosition(for: 120.0) == 0)
        #expect(geometry.yPosition(for: 10.0) == 100)
    }

    @Test func aZeroHeightLaneDoesNotDivideByZero() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 0)
        #expect(geometry.yPosition(for: 85.0).isFinite)
    }

    @Test func aDegenerateRangeDoesNotDivideByZero() {
        let geometry = VitalsLaneGeometry(minValue: 90, maxValue: 90, laneHeight: 100)
        #expect(geometry.yPosition(for: 90.0).isFinite)
    }

    @Test func theStandardScalesMatchTheDesign() {
        #expect(VitalsLaneGeometry.spo2(laneHeight: 60).minValue == 70)
        #expect(VitalsLaneGeometry.spo2(laneHeight: 60).maxValue == 100)
        #expect(VitalsLaneGeometry.pulse(laneHeight: 60).minValue == 30)
        #expect(VitalsLaneGeometry.pulse(laneHeight: 60).maxValue == 110)
    }

    /// The lanes and the stage plot must agree on x for the same viewport, or pinch and
    /// pan would visibly desynchronise them.
    @Test func vitalsAndSleepAgreeOnXForTheSameViewport() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let viewport = TimelineViewport(start: start, end: start.addingTimeInterval(3600))
        let sleep = SleepTimelineGeometry(
            totalStart: start, totalEnd: start.addingTimeInterval(7200),
            viewport: viewport, canvasWidth: 400, canvasHeight: 300
        )
        let lanes = SleepTimelineGeometry(
            totalStart: start, totalEnd: start.addingTimeInterval(7200),
            viewport: viewport, canvasWidth: 400, canvasHeight: 80
        )
        for minutes in stride(from: 0, through: 60, by: 10) {
            let moment = start.addingTimeInterval(Double(minutes) * 60)
            #expect(sleep.xPosition(for: moment) == lanes.xPosition(for: moment))
        }
    }
}
