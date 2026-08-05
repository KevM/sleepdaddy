import Testing
import Foundation
@testable import SleepDaddy

struct CheckmeTimestampTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    @Test func parsesTheDeviceFormat() throws {
        let date = try #require(CheckmeTimestamp.parse("18:02:48 Aug 03 2026", calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 3)
        #expect(parts.hour == 18)
        #expect(parts.minute == 2)
        #expect(parts.second == 48)
    }

    @Test func parsesEveryMonthAbbreviation() {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        for (offset, name) in names.enumerated() {
            let parsed = CheckmeTimestamp.parse("00:00:00 \(name) 01 2026", calendar: calendar)
            #expect(parsed != nil, "month \(name) failed to parse")
            let month = calendar.dateComponents([.month], from: parsed!).month
            #expect(month == offset + 1)
        }
    }

    @Test func parsesAcrossMidnight() throws {
        let before = try #require(CheckmeTimestamp.parse("23:59:58 Aug 03 2026", calendar: calendar))
        let after = try #require(CheckmeTimestamp.parse("00:00:00 Aug 04 2026", calendar: calendar))
        #expect(after.timeIntervalSince(before) == 2)
    }

    @Test func rejectsMalformedInput() {
        #expect(CheckmeTimestamp.parse("", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("18:02:48 Aug 03", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("18:02 Aug 03 2026", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("18:02:48 Xyz 03 2026", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("aa:bb:cc Aug 03 2026", calendar: calendar) == nil)
    }
}
