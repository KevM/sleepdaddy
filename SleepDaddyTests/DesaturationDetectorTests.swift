import Testing
import Foundation
@testable import SleepDaddy

struct DesaturationDetectorTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func session(_ spo2: [UInt8]) -> VitalsSession {
        VitalsSession(
            id: "t", startDate: epoch, spo2: spo2,
            pulse: Array(repeating: UInt8(60), count: spo2.count),
            motion: Array(repeating: UInt8(0), count: spo2.count),
            sourceFileNames: []
        )
    }

    /// 60 samples of baseline, then a dip, then recovery.
    private func dipSession(baseline: UInt8, nadir: UInt8, dipLength: Int) -> VitalsSession {
        var values = [UInt8](repeating: baseline, count: 60)
        values += [UInt8](repeating: nadir, count: dipLength)
        values += [UInt8](repeating: baseline, count: 60)
        return session(values)
    }

    @Test func detectsASingleFourPercentDrop() {
        let events = DesaturationDetector().events(in: dipSession(baseline: 95, nadir: 91, dipLength: 10))
        #expect(events.count == 1)
        #expect(events[0].nadir == 91)
        #expect(events[0].baseline == 95)
        #expect(events[0].dropAmount == 4)
    }

    @Test func ignoresADropSmallerThanTheThreshold() {
        let events = DesaturationDetector().events(in: dipSession(baseline: 95, nadir: 92, dipLength: 10))
        #expect(events.isEmpty)
    }

    @Test func recordsTheDeepestPointNotTheFirst() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [90, 84, 79, 84, 90]
        values += [UInt8](repeating: 96, count: 60)
        let events = DesaturationDetector().events(in: session(values))
        #expect(events.count == 1)
        #expect(events[0].nadir == 79)
    }

    @Test func detectsTwoSeparatedEvents() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 88, count: 10)
        values += [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 87, count: 10)
        values += [UInt8](repeating: 96, count: 60)
        #expect(DesaturationDetector().events(in: session(values)).count == 2)
    }

    @Test func missingReadingsProduceNoEvents() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 0, count: 30)   // sensor off the finger
        values += [UInt8](repeating: 96, count: 60)
        #expect(DesaturationDetector().events(in: session(values)).isEmpty)
    }

    @Test func aFlatRecordingProducesNoEvents() {
        #expect(DesaturationDetector().events(in: session(Array(repeating: 96, count: 500))).isEmpty)
    }

    @Test func aRecordingShorterThanTheBaselineWindowProducesNoEvents() {
        #expect(DesaturationDetector().events(in: session(Array(repeating: 96, count: 10))).isEmpty)
    }

    @Test func anEmptySessionProducesNoEvents() {
        #expect(DesaturationDetector().events(in: session([])).isEmpty)
    }

    @Test func eventDatesMapBackOntoTheSession() {
        let subject = dipSession(baseline: 95, nadir: 88, dipLength: 10)
        let events = DesaturationDetector().events(in: subject)
        #expect(events.count == 1)
        #expect(events[0].startDate >= subject.startDate)
        #expect(events[0].endDate <= subject.endDate)
        #expect(events[0].endDate > events[0].startDate)
    }

    @Test func railEventsAreThoseReachingBelowNinety() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 91, count: 10)   // a 5% drop, but nadir stays >= 90
        values += [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 86, count: 10)   // reaches below 90
        values += [UInt8](repeating: 96, count: 60)

        let all = DesaturationDetector().events(in: session(values))
        #expect(all.count == 2)

        let rail = all.filter(\.reachesRailThreshold)
        #expect(rail.count == 1)
        #expect(rail[0].nadir == 86)
    }

    @Test func terminalEventIncludesTheFinalSamplesWholeSlot() throws {
        var values = [UInt8](repeating: 96, count: 60)
        values.append(82)
        let event = try #require(DesaturationDetector().events(in: session(values)).first)

        #expect(event.duration == VitalsSession.sampleInterval)
        #expect(event.endDate == epoch.addingTimeInterval(61 * VitalsSession.sampleInterval))
    }
}
