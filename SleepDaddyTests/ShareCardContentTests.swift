import Foundation
import Testing
@testable import SleepDaddy

struct ShareCardContentTests {
    private static let utc = TimeZone(secondsFromGMT: 0)!

    private static func date(
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
            night, calendar: calendar, locale: Locale(identifier: "en_US")
        )

        #expect(header == "Fri, Jul 31, 2026")
    }

    @Test func dateHeaderKeepsTheYearForAnEarlierYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let night = Self.date(year: 2025, month: 7, day: 31, hour: 22, minute: 45)

        let header = AccessibilityHelpers.formattedDateHeader(
            night, calendar: calendar, locale: Locale(identifier: "en_US")
        )

        #expect(header == "Thu, Jul 31, 2025")
    }
}
