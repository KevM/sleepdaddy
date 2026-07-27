import Foundation

/// The visible time window of the sleep timeline.
///
/// A viewport is always a forward-running, non-empty range. Clamping it against
/// the bounds of a night is the responsibility of `SleepTimelineGeometry`.
public struct TimelineViewport: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        precondition(end > start, "TimelineViewport end must follow start")
        self.start = start
        self.end = end
    }

    /// Builds a viewport from two loose dates, widening a degenerate or inverted
    /// range to a one-second minimum.
    ///
    /// Temporary bridge for callers that still store `start`/`end` as independent
    /// `Date` values; remove once `NightBrowserModel` stores a `TimelineViewport`.
    public init(normalizing start: Date, end: Date) {
        self.init(start: start, end: max(end, start.addingTimeInterval(1)))
    }

    /// Length of the visible window in seconds.
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// The date at the horizontal centre of the window.
    public var midpoint: Date { start.addingTimeInterval(duration / 2) }

    /// Translates the window in time, preserving its duration.
    public func shifted(by interval: TimeInterval) -> Self {
        Self(start: start.addingTimeInterval(interval),
             end: end.addingTimeInterval(interval))
    }
}
