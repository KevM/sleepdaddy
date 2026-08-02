import Foundation
import Testing
@testable import SleepDaddy

struct CombinedTimelineRailTests {
    @Test func timeLabelsHonorLocaleHourCycle() {
        let date = Date(timeIntervalSince1970: 12 * 60 * 60 + 5 * 60)
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let usTime = CombinedTimelineRail.formattedTime(
            date,
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone
        )
        let ukTime = CombinedTimelineRail.formattedTime(
            date,
            locale: Locale(identifier: "en_GB"),
            timeZone: timeZone
        )

        #expect(usTime.contains("12:05"))
        #expect(usTime.contains("PM"))
        #expect(ukTime.contains("12:05"))
        #expect(!ukTime.contains("PM"))
    }
}
