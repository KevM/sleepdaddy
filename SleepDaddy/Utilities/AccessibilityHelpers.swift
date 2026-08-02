import SwiftUI

public struct AccessibilityHelpers {
    public static func formattedTimeInterval(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(round(interval / 60.0))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    /// "Fri, Jul 31, 2026".
    ///
    /// Abbreviated rather than `.full` ("Friday, July 31, 2026"), which cost the share card
    /// most of a line. The year stays: a shared image outlives the moment it was taken, and
    /// the reader has no other cue for which year the night belongs to.
    public static func formattedDateHeader(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .month(.abbreviated)
            .day()
            .year()
            .locale(locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    private nonisolated static let clockStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened
    )

    /// The single clock-time formatter in the app. `CombinedTimelineRail` renders its axis
    /// labels with this, and `formattedTimeRange` composes two of them.
    public static func formattedClockTime(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var style = clockStyle.locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Two clock times joined by an en dash.
    ///
    /// Deliberately not `DateIntervalFormatter`: that type ignores `dateStyle = .none` and
    /// prints both calendar dates once a range crosses midnight, which every night's sleep
    /// does.
    public static func formattedTimeRange(
        start: Date,
        end: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let from = formattedClockTime(start, locale: locale, timeZone: timeZone)
        let to = formattedClockTime(end, locale: locale, timeZone: timeZone)
        return "\(from) – \(to)"
    }
}

private struct AccessibilityReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    public var accessibilityReduceMotionOverride: Bool? {
        get { self[AccessibilityReduceMotionOverrideKey.self] }
        set { self[AccessibilityReduceMotionOverrideKey.self] = newValue }
    }
}
