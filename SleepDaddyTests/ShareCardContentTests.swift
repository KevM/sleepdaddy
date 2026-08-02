import Foundation
import Testing
@testable import SleepDaddy

/// Nights built from a bare list of stages, so a test can say exactly which stages are
/// present without caring what a realistic night looks like.
enum ShareCardFixtures {
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute
            )
        )!
    }

    static func night(with stages: [SleepStage]) -> AssembledNight {
        let base = date(year: 2026, month: 7, day: 31, hour: 22, minute: 0)
        var intervals: [NormalizedSleepInterval] = []
        for (offset, stage) in stages.enumerated() {
            intervals.append(
                NormalizedSleepInterval(
                    id: "\(stage.rawValue)-\(offset)",
                    startDate: base.addingTimeInterval(Double(offset) * 3600),
                    endDate: base.addingTimeInterval(Double(offset + 1) * 3600),
                    stage: stage,
                    sourceName: "Apple Watch",
                    sourceIdentifier: "com.apple.health"
                )
            )
        }

        return AssembledNight(
            date: base,
            coreWindowStart: base,
            coreWindowEnd: base.addingTimeInterval(8 * 3600),
            detectedStart: base,
            detectedEnd: base.addingTimeInterval(8 * 3600),
            rawIntervals: intervals,
            primaryLaneIntervals: intervals.filter { $0.stage != .inBed },
            displayLaneIntervals: intervals.filter { $0.stage != .inBed },
            conflicts: [],
            summary: .empty,
            hasSleepData: true
        )
    }
}

struct ShareCardContentTests {
    private static let utc = ShareCardFixtures.utc

    private static func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int
    ) -> Date {
        ShareCardFixtures.date(
            year: year, month: month, day: day, hour: hour, minute: minute
        )
    }

    /// Collapses the narrow no-break space (U+202F) ICU puts before AM/PM into a plain space.
    ///
    /// The app should keep whatever separator the locale asks for; asserting on an invisible
    /// character only records which Unicode space Apple shipped this release.
    private static func normalizingSpaces(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Regression lock for the `DateIntervalFormatter` fault: it ignored `dateStyle = .none`
    /// and printed both calendar dates for any range crossing midnight.
    @Test func timeRangeCrossingMidnightPrintsOnlyClockTimes() {
        let start = Self.date(year: 2026, month: 7, day: 31, hour: 22, minute: 45)
        let end = Self.date(year: 2026, month: 8, day: 1, hour: 7, minute: 17)

        let formatted = AccessibilityHelpers.formattedTimeRange(
            start: start,
            end: end,
            locale: Locale(identifier: "en_US"),
            timeZone: Self.utc
        )

        #expect(Self.normalizingSpaces(formatted) == "10:45 PM – 7:17 AM")
    }

    @Test func clockTimeHonorsLocaleHourCycle() {
        let noon = Self.date(year: 2026, month: 7, day: 31, hour: 12, minute: 5)

        let us = AccessibilityHelpers.formattedClockTime(
            noon, locale: Locale(identifier: "en_US"), timeZone: Self.utc
        )
        let uk = AccessibilityHelpers.formattedClockTime(
            noon, locale: Locale(identifier: "en_GB"), timeZone: Self.utc
        )

        #expect(Self.normalizingSpaces(us) == "12:05 PM")
        #expect(uk == "12:05")
    }

    @Test func dateHeaderAbbreviatesTheWeekdayAndMonthButKeepsTheYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let night = Self.date(year: 2026, month: 7, day: 31, hour: 22, minute: 45)

        let header = AccessibilityHelpers.formattedDateHeader(
            night,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: Self.utc
        )

        #expect(header == "Fri, Jul 31, 2026")
    }

    @Test func dateHeaderKeepsTheYearForAnEarlierYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let night = Self.date(year: 2025, month: 7, day: 31, hour: 22, minute: 45)

        let header = AccessibilityHelpers.formattedDateHeader(
            night,
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            timeZone: Self.utc
        )

        #expect(header == "Thu, Jul 31, 2025")
    }

    private static func night(with stages: [SleepStage]) -> AssembledNight {
        ShareCardFixtures.night(with: stages)
    }

    @Test func legendIsEmptyWhenTheAxisAlreadyLabelsEveryStage() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.awake, .rem, .core, .deep])
        )

        #expect(stages.isEmpty)
    }

    @Test func legendNamesUnspecifiedSleepWhenPresent() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.core, .asleepUnspecified])
        )

        #expect(stages == [.asleepUnspecified])
    }

    @Test func legendNamesInBedWhenPresent() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.core, .inBed])
        )

        #expect(stages == [.inBed])
    }

    /// Two chips is the maximum the rule can ever produce, which is what makes a second
    /// legend row structurally impossible rather than merely unlikely. The order follows
    /// `SleepStage.allCases`.
    @Test func legendNamesBothUnlabelledStagesInDeclarationOrder() {
        let stages = ShareTimelineCardView.legendStages(
            for: Self.night(with: [.core, .inBed, .asleepUnspecified])
        )

        #expect(stages == [.asleepUnspecified, .inBed])
    }
}
