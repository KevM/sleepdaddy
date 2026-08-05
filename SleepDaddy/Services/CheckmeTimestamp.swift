import Foundation

/// Parses the Checkme O2 Max timestamp format: `18:02:48 Aug 03 2026`.
///
/// The format carries **no timezone**, so values are resolved in the supplied calendar's
/// zone — the device's current zone in production. See the design document's timezone
/// limitation.
///
/// `DateFormatter` is deliberately not used: it costs roughly 10–50 µs per call, and a
/// full recording is 22,000 rows. `CheckmeCSVParser` calls this exactly twice per file.
public enum CheckmeTimestamp {
    private static let monthNames = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12
    ]

    public static func parse(_ text: Substring, calendar: Calendar) -> Date? {
        let fields = text.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 4 else { return nil }

        let clock = fields[0].split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 3,
              let hour = Int(clock[0]),
              let minute = Int(clock[1]),
              let second = Int(clock[2]),
              let month = monthNames[String(fields[1])],
              let day = Int(fields[2]),
              let year = Int(fields[3])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }

    public static func parse(_ text: String, calendar: Calendar) -> Date? {
        parse(text[text.startIndex...], calendar: calendar)
    }
}
