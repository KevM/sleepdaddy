import Testing
import Foundation
@testable import SleepDaddy

struct VitalsSessionTests {
    private func makeSession(count: Int, start: Date = Date(timeIntervalSinceReferenceDate: 0)) -> VitalsSession {
        VitalsSession(
            id: "test",
            startDate: start,
            spo2: Array(repeating: UInt8(95), count: count),
            pulse: Array(repeating: UInt8(60), count: count),
            motion: Array(repeating: UInt8(0), count: count),
            sourceFileNames: ["a.csv"]
        )
    }

    @Test func sampleCountReflectsTheColumns() {
        #expect(makeSession(count: 10).sampleCount == 10)
    }

    @Test func endDateIsDerivedFromTheFixedCadence() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        // 10 samples at 2s: the last sample sits 18s after the first.
        #expect(session.endDate == start.addingTimeInterval(18))
    }

    @Test func dateForIndexUsesArithmeticNotStoredTimestamps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        #expect(session.date(at: 0) == start)
        #expect(session.date(at: 5) == start.addingTimeInterval(10))
    }

    @Test func indexForDateFloorsIntoTheContainingSample() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        #expect(session.index(for: start) == 0)
        #expect(session.index(for: start.addingTimeInterval(1.9)) == 0)
        #expect(session.index(for: start.addingTimeInterval(2.0)) == 1)
        #expect(session.index(for: start.addingTimeInterval(-3)) == -2)
        #expect(session.index(for: start.addingTimeInterval(-5)) == -3)
    }

    @Test func zeroMeansMissing() {
        let session = VitalsSession(
            id: "t", startDate: Date(timeIntervalSinceReferenceDate: 0),
            spo2: [95, 0, 96], pulse: [60, 0, 61], motion: [0, 0, 0],
            sourceFileNames: []
        )
        #expect(session.spo2Value(at: 0) == 95)
        #expect(session.spo2Value(at: 1) == nil)
        #expect(session.pulseValue(at: 1) == nil)
    }

    @Test func dateIntervalSpansTheWholeRecording() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        #expect(session.dateInterval.start == start)
        #expect(session.dateInterval.end == start.addingTimeInterval(18))
    }
}
