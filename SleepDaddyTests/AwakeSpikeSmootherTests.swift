import Testing
import Foundation
@testable import SleepDaddy

struct AwakeSpikeSmootherTests {
    private let smoother = AwakeSpikeSmoother()
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func interval(
        _ id: String,
        _ stage: SleepStage,
        from: TimeInterval,
        to: TimeInterval,
        source: String = "com.apple.health"
    ) -> NormalizedSleepInterval {
        NormalizedSleepInterval(
            id: id,
            startDate: origin.addingTimeInterval(from),
            endDate: origin.addingTimeInterval(to),
            stage: stage,
            sourceName: source,
            sourceIdentifier: source
        )
    }

    @Test func testBriefAwakeBetweenMatchingStagesCollapsesToOneInterval() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("c2", .core, from: 660, to: 1200)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].startDate == origin)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(1200))
    }

    @Test func testAwakeJustOverThresholdIsKept() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 661),
            interval("c2", .core, from: 661, to: 1200)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testTwoMinuteAwakeIsKept() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 720),
            interval("c2", .core, from: 720, to: 1200)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testLaneWithoutBriefAwakesIsUnchanged() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("r1", .rem, from: 600, to: 1200)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testBriefAwakeBetweenDifferentStagesExtendsPredecessor() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("r1", .rem, from: 660, to: 1200)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 2)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(660))
        #expect(smoothed[1].stage == .rem)
        #expect(smoothed[1].startDate == origin.addingTimeInterval(660))
    }

    @Test func testBriefAwakeAtHeadIsAbsorbedByFollowingInterval() {
        let lane = [
            interval("a1", .awake, from: 0, to: 60),
            interval("c1", .core, from: 60, to: 600)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].startDate == origin)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(600))
    }

    @Test func testBriefAwakeAtTailIsAbsorbedByPrecedingInterval() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].stage == .core)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(660))
    }

    @Test func testMultipleBriefAwakesRemovedInOnePass() {
        let lane = [
            interval("c1", .core, from: 0, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("c2", .core, from: 660, to: 900),
            interval("a2", .awake, from: 900, to: 960),
            interval("c3", .core, from: 960, to: 1200)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 1)
        #expect(smoothed[0].startDate == origin)
        #expect(smoothed[0].endDate == origin.addingTimeInterval(1200))
    }

    @Test func testLaneOfOnlyBriefAwakesIsReturnedUnchanged() {
        let lane = [
            interval("a1", .awake, from: 0, to: 60),
            interval("a2", .awake, from: 120, to: 180)
        ]

        #expect(smoother.smooth(lane: lane) == lane)
    }

    @Test func testEmptyLaneIsReturnedUnchanged() {
        #expect(smoother.smooth(lane: []).isEmpty)
    }

    @Test func testSmoothedLaneCoversTheSameSpan() {
        let lane = [
            interval("a0", .awake, from: 0, to: 60),
            interval("c1", .core, from: 60, to: 600),
            interval("a1", .awake, from: 600, to: 660),
            interval("r1", .rem, from: 660, to: 1200),
            interval("a2", .awake, from: 1200, to: 1260)
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.first?.startDate == lane.first?.startDate)
        #expect(smoothed.last?.endDate == lane.last?.endDate)
    }

    @Test func testSameStageFromDifferentSourcesIsNotCoalesced() {
        let lane = [
            interval("c1", .core, from: 0, to: 600, source: "com.apple.health"),
            interval("a1", .awake, from: 600, to: 660, source: "com.apple.health"),
            interval("c2", .core, from: 660, to: 1200, source: "com.oura.ring")
        ]

        let smoothed = smoother.smooth(lane: lane)

        #expect(smoothed.count == 2)
        #expect(smoothed[0].sourceIdentifier == "com.apple.health")
        #expect(smoothed[0].endDate == origin.addingTimeInterval(660))
        #expect(smoothed[1].sourceIdentifier == "com.oura.ring")
        #expect(smoothed[1].startDate == origin.addingTimeInterval(660))
    }
}
