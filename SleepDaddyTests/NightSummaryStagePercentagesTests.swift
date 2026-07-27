import Testing
import Foundation
@testable import SleepDaddy

struct NightSummaryStagePercentagesTests {
    /// Builds a summary carrying only the stage durations under test.
    /// The other fields do not affect `stagePercentages`.
    private func makeSummary(
        awake: TimeInterval = 0,
        rem: TimeInterval = 0,
        core: TimeInterval = 0,
        deep: TimeInterval = 0,
        unspecified: TimeInterval = 0,
        inBed: TimeInterval = 0
    ) -> NightSummary {
        NightSummary(
            totalSleepDuration: rem + core + deep + unspecified,
            awakeDuration: awake,
            inBedDuration: inBed,
            stageDurations: [
                .awake: awake,
                .rem: rem,
                .core: core,
                .deep: deep,
                .asleepUnspecified: unspecified,
                .inBed: inBed
            ],
            conflictCount: 0
        )
    }

    private let minute: TimeInterval = 60

    @Test func percentageStagesMatchesDefaultDisplayedStages() {
        #expect(NightSummary.percentageStages == SleepTimelineGeometry.defaultDisplayedStages)
    }

    @Test func percentagesSumToOneHundredForATypicalNight() {
        let summary = makeSummary(
            awake: 18 * minute,
            rem: 99 * minute,
            core: 231 * minute,
            deep: 104 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 4)
        #expect(percentages[.rem] == 22)
        #expect(percentages[.core] == 51)
        #expect(percentages[.deep] == 23)
        #expect(percentages.values.reduce(0, +) == 100)
    }

    @Test func equalDurationsSplitEvenly() {
        let summary = makeSummary(
            awake: 60 * minute,
            rem: 60 * minute,
            core: 60 * minute,
            deep: 60 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 25)
        #expect(percentages[.rem] == 25)
        #expect(percentages[.core] == 25)
        #expect(percentages[.deep] == 25)
    }

    /// Independent rounding of 17.5/27.5/27.5/27.5 would total 102.
    /// Largest remainder must keep the column at 100, and the three-way tie
    /// among the .5 remainders must be resolved by row order.
    @Test func largestRemainderPreventsOvershootAndBreaksTiesByRowOrder() {
        let summary = makeSummary(
            awake: 17.5 * minute,
            rem: 27.5 * minute,
            core: 27.5 * minute,
            deep: 27.5 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 18)
        #expect(percentages[.rem] == 28)
        #expect(percentages[.core] == 27)
        #expect(percentages[.deep] == 27)
        #expect(percentages.values.reduce(0, +) == 100)
    }

    @Test func unspecifiedAndInBedAreExcludedFromTheDenominator() {
        let summary = makeSummary(
            core: 30 * minute,
            deep: 30 * minute,
            unspecified: 60 * minute,
            inBed: 480 * minute
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.core] == 50)
        #expect(percentages[.deep] == 50)
        #expect(percentages[.awake] == 0)
        #expect(percentages[.rem] == 0)
        #expect(percentages[.asleepUnspecified] == nil)
        #expect(percentages[.inBed] == nil)
        #expect(percentages.values.reduce(0, +) == 100)
    }

    @Test func aNightOfOnlyUnspecifiedSleepHasNoPercentages() {
        let summary = makeSummary(unspecified: 440 * minute, inBed: 480 * minute)

        #expect(summary.stagePercentages.isEmpty)
    }

    @Test func anEmptySummaryHasNoPercentages() {
        #expect(NightSummary.empty.stagePercentages.isEmpty)
    }

    @Test func missingStageKeysCountAsZero() {
        let summary = NightSummary(
            totalSleepDuration: 120 * minute,
            awakeDuration: 0,
            inBedDuration: 0,
            stageDurations: [.core: 90 * minute, .deep: 30 * minute],
            conflictCount: 0
        )

        let percentages = summary.stagePercentages

        #expect(percentages[.awake] == 0)
        #expect(percentages[.rem] == 0)
        #expect(percentages[.core] == 75)
        #expect(percentages[.deep] == 25)
    }
}
