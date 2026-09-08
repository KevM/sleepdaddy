import Testing
import Foundation
@testable import SleepDaddy

struct VitalsEnvelopeBuilderTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func session(spo2: [UInt8], pulse: [UInt8]? = nil) -> VitalsSession {
        VitalsSession(
            id: "t",
            startDate: epoch,
            spo2: spo2,
            pulse: pulse ?? Array(repeating: UInt8(60), count: spo2.count),
            motion: Array(repeating: UInt8(0), count: spo2.count),
            sourceFileNames: []
        )
    }

    private func fullViewport(_ session: VitalsSession) -> TimelineViewport {
        TimelineViewport(start: session.startDate, end: session.endDate)
    }

    /// A 22,000-sample night with one brief severe dip — the shape that matters.
    private func nightWithOneDip(nadir: UInt8 = 73) -> VitalsSession {
        var values = [UInt8](repeating: 95, count: 22_000)
        for index in 11_000..<11_019 { values[index] = nadir }
        return session(spo2: values)
    }

    @Test func aSingleSevereDipSurvivesReductionToOneHundredColumns() {
        let session = nightWithOneDip()
        let envelope = VitalsEnvelopeBuilder().build(
            session: session, viewport: fullViewport(session), pixelWidth: 100
        )
        let lowest = envelope.columns.compactMap(\.spo2Min).min()
        #expect(lowest == 73)
    }

    @Test func aSingleSevereDipSurvivesReductionToTenColumns() {
        let session = nightWithOneDip()
        let envelope = VitalsEnvelopeBuilder().build(
            session: session, viewport: fullViewport(session), pixelWidth: 10
        )
        #expect(envelope.columns.compactMap(\.spo2Min).min() == 73)
    }

    @Test func aSingleSevereDipSurvivesReductionToOneColumn() {
        let session = nightWithOneDip()
        let envelope = VitalsEnvelopeBuilder().build(
            session: session, viewport: fullViewport(session), pixelWidth: 1
        )
        #expect(envelope.columns.count == 1)
        #expect(envelope.columns[0].spo2Min == 73)
        #expect(envelope.columns[0].spo2Max == 95)
    }

    @Test func theMaximumSurvivesTheSameReduction() {
        var values = [UInt8](repeating: 90, count: 5_000)
        values[2_500] = 99
        let built = VitalsEnvelopeBuilder().build(
            session: session(spo2: values),
            viewport: fullViewport(session(spo2: values)),
            pixelWidth: 20
        )
        #expect(built.columns.compactMap(\.spo2Max).max() == 99)
    }

    @Test func missingReadingsProduceAnEmptyColumnRatherThanABridge() {
        // All-missing middle third must not be spanned by the neighbours.
        var values = [UInt8](repeating: 95, count: 300)
        for index in 100..<200 { values[index] = 0 }
        let subject = session(spo2: values)
        let exactViewport = TimelineViewport(start: epoch, end: epoch.addingTimeInterval(600))
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: exactViewport, pixelWidth: 3
        )
        #expect(envelope.columns[0].spo2Min == 95)
        #expect(envelope.columns[1].spo2Min == nil)
        #expect(envelope.columns[1].spo2Max == nil)
        #expect(envelope.columns[2].spo2Min == 95)
    }

    @Test func finalSampleIsIncludedInFullViewport() {
        let subject = session(spo2: [90, 91, 92, 99])
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: fullViewport(subject), pixelWidth: 4
        )
        #expect(envelope.columns.last?.spo2Max == 99)
    }

    @Test func pulseIsEnvelopedIndependentlyOfSpO2() {
        let subject = session(spo2: [95, 95, 95, 95], pulse: [40, 80, 50, 70])
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: fullViewport(subject), pixelWidth: 1
        )
        #expect(envelope.columns[0].pulseMin == 40)
        #expect(envelope.columns[0].pulseMax == 80)
    }

    @Test func aViewportOutsideTheRecordingProducesEmptyColumns() {
        let subject = session(spo2: [95, 95, 95])
        let far = TimelineViewport(
            start: epoch.addingTimeInterval(86_400),
            end: epoch.addingTimeInterval(90_000)
        )
        let envelope = VitalsEnvelopeBuilder().build(session: subject, viewport: far, pixelWidth: 5)
        #expect(envelope.columns.count == 5)
        #expect(envelope.columns.allSatisfy { $0.spo2Min == nil })
    }

    @Test func aViewportOverlappingOnlyPartOfTheRecordingClipsCleanly() {
        let subject = session(spo2: [90, 91, 92, 93])
        // Starts one full recording-length before the data.
        let viewport = TimelineViewport(
            start: epoch.addingTimeInterval(-6),
            end: epoch.addingTimeInterval(2)
        )
        let envelope = VitalsEnvelopeBuilder().build(session: subject, viewport: viewport, pixelWidth: 4)
        #expect(envelope.columns.count == 4)
        #expect(envelope.columns.compactMap(\.spo2Min).min() == 90)
    }

    @Test func zeroOrNegativePixelWidthProducesNoColumnsRatherThanCrashing() {
        let subject = session(spo2: [95, 95])
        #expect(VitalsEnvelopeBuilder().build(session: subject, viewport: fullViewport(subject), pixelWidth: 0).columns.isEmpty)
        #expect(VitalsEnvelopeBuilder().build(session: subject, viewport: fullViewport(subject), pixelWidth: -3).columns.isEmpty)
    }

    @Test func anEmptySessionProducesEmptyColumnsRatherThanCrashing() {
        let empty = session(spo2: [])
        let viewport = TimelineViewport(start: epoch, end: epoch.addingTimeInterval(60))
        let envelope = VitalsEnvelopeBuilder().build(session: empty, viewport: viewport, pixelWidth: 4)
        #expect(envelope.columns.count == 4)
        #expect(envelope.columns.allSatisfy { $0.isEmpty })
    }

    @Test func zoomedPastOneToOneEveryColumnStillCarriesASample() {
        // 4 samples across 40 columns: each sample is held for its two seconds.
        let subject = session(spo2: [90, 91, 92, 93])
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: fullViewport(subject), pixelWidth: 40
        )
        #expect(envelope.columns.allSatisfy { !$0.isEmpty })
        #expect(envelope.columns.compactMap(\.spo2Min).min() == 90)
        #expect(envelope.columns.compactMap(\.spo2Max).max() == 93)
    }
}
