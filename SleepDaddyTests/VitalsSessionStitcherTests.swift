import Testing
import Foundation
@testable import SleepDaddy

struct VitalsSessionStitcherTests {
    private func session(id: String, start: Date, count: Int, spo2: UInt8 = 95) -> VitalsSession {
        VitalsSession(
            id: id,
            startDate: start,
            spo2: Array(repeating: spo2, count: count),
            pulse: Array(repeating: UInt8(60), count: count),
            motion: Array(repeating: UInt8(0), count: count),
            sourceFileNames: [id]
        )
    }

    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    @Test func joinsTheReferenceFourSecondGap() {
        // Mirrors the real export: 18,000 samples then a resume 4 s later.
        let first = session(id: "a", start: epoch, count: 18_000)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(4), count: 100)

        let result = VitalsSessionStitcher().stitch([first, second])

        #expect(result.count == 1)
        #expect(result[0].sampleCount == 18_101)
        #expect(result[0].sourceFileNames == ["a", "b"])
        #expect(result[0].startDate == epoch)
    }

    @Test func aFortyMinuteGapStaysTwoSessions() {
        let first = session(id: "a", start: epoch, count: 100)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(40 * 60), count: 100)

        let result = VitalsSessionStitcher().stitch([first, second])

        #expect(result.count == 2)
    }

    @Test func joinsAThreeFileChain() {
        let first = session(id: "a", start: epoch, count: 50)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(2), count: 50)
        let third = session(id: "c", start: second.endDate.addingTimeInterval(2), count: 50)

        let result = VitalsSessionStitcher().stitch([third, first, second])

        #expect(result.count == 1)
        #expect(result[0].sampleCount == 150)
        #expect(result[0].sourceFileNames == ["a", "b", "c"])
    }

    @Test func sortsOutOfOrderInput() {
        let first = session(id: "a", start: epoch, count: 50)
        let later = session(id: "z", start: epoch.addingTimeInterval(86_400), count: 50)

        let result = VitalsSessionStitcher().stitch([later, first])

        #expect(result.count == 2)
        #expect(result[0].id == first.id)
        #expect(result[1].id == later.id)
    }

    @Test func padsTheGapSoSampleIndicesStayAlignedToTheCadence() {
        // A 4 s gap is one missing sample slot. Concatenating without padding would
        // shift every later sample 2 s early and silently misalign the whole tail.
        let first = session(id: "a", start: epoch, count: 10, spo2: 95)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(4), count: 10, spo2: 88)

        let result = VitalsSessionStitcher().stitch([first, second])[0]

        #expect(result.sampleCount == 21)
        #expect(result.spo2Value(at: 10) == nil)   // the padded slot reads as a gap
        #expect(result.spo2Value(at: 11) == 88)
        #expect(result.date(at: 11) == second.startDate)
    }

    @Test func emptyInputProducesNoSessions() {
        #expect(VitalsSessionStitcher().stitch([]).isEmpty)
    }

    @Test func aSingleSessionPassesThroughUnchanged() {
        let only = session(id: "a", start: epoch, count: 10)
        let result = VitalsSessionStitcher().stitch([only])
        #expect(result.count == 1)
        #expect(result[0].sampleCount == 10)
    }
}
