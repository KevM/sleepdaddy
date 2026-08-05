import Testing
import Foundation
@testable import SleepDaddy

struct AssembledNightExtentTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func night(
        coreStart: TimeInterval, coreEnd: TimeInterval,
        detectedStart: TimeInterval, detectedEnd: TimeInterval,
        vitals: DateInterval? = nil
    ) -> AssembledNight {
        AssembledNight(
            date: epoch,
            coreWindowStart: epoch.addingTimeInterval(coreStart),
            coreWindowEnd: epoch.addingTimeInterval(coreEnd),
            detectedStart: epoch.addingTimeInterval(detectedStart),
            detectedEnd: epoch.addingTimeInterval(detectedEnd),
            rawIntervals: [], primaryLaneIntervals: [], displayLaneIntervals: [],
            conflicts: [], summary: .empty, hasSleepData: true,
            vitalsExtent: vitals
        )
    }

    @Test func withoutVitalsTheExtentFollowsTheDetectedSpanNotTheCoreWindow() {
        // Core window 0–43200; sleep only occupied 14400–28800.
        let subject = night(coreStart: 0, coreEnd: 43_200, detectedStart: 14_400, detectedEnd: 28_800)

        #expect(subject.timelineStart == subject.preferredViewportStart)
        #expect(subject.timelineEnd == subject.preferredViewportEnd)
        // The old behaviour floored to the core window; it no longer does.
        #expect(subject.timelineStart > subject.coreWindowStart)
    }

    @Test func vitalsStartingEarlierWidenTheExtent() {
        let vitalsStart = epoch.addingTimeInterval(10_000)
        let subject = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(start: vitalsStart, end: epoch.addingTimeInterval(30_000))
        )

        #expect(subject.timelineStart == vitalsStart)
        #expect(subject.timelineEnd == epoch.addingTimeInterval(30_000))
    }

    @Test func vitalsInsideTheSleepSpanDoNotNarrowTheExtent() {
        let subject = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(
                start: epoch.addingTimeInterval(20_000),
                end: epoch.addingTimeInterval(21_000)
            )
        )

        #expect(subject.timelineStart == subject.preferredViewportStart)
        #expect(subject.timelineEnd == subject.preferredViewportEnd)
    }

    @Test func theOpeningViewportIsUnaffectedByVitals() {
        let withoutVitals = night(coreStart: 0, coreEnd: 43_200, detectedStart: 14_400, detectedEnd: 28_800)
        let withVitals = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(start: epoch, end: epoch.addingTimeInterval(40_000))
        )

        #expect(withoutVitals.preferredViewportStart == withVitals.preferredViewportStart)
        #expect(withoutVitals.preferredViewportEnd == withVitals.preferredViewportEnd)
    }

    @Test func thePreferredViewportAlwaysFitsInsideTheExtent() {
        let subject = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(start: epoch, end: epoch.addingTimeInterval(40_000))
        )

        #expect(subject.timelineStart <= subject.preferredViewportStart)
        #expect(subject.timelineEnd >= subject.preferredViewportEnd)
    }

    @Test func attachingAnExtentPreservesEveryOtherField() {
        let base = night(coreStart: 0, coreEnd: 43_200, detectedStart: 14_400, detectedEnd: 28_800)
        let extent = DateInterval(start: epoch, end: epoch.addingTimeInterval(40_000))
        let attached = base.withVitalsExtent(extent)

        #expect(attached.vitalsExtent == extent)
        #expect(attached.date == base.date)
        #expect(attached.detectedStart == base.detectedStart)
        #expect(attached.detectedEnd == base.detectedEnd)
        #expect(attached.hasSleepData == base.hasSleepData)
        #expect(attached.summary == base.summary)
    }
}
