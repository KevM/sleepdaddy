import Foundation

public struct AssembledNight: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    public let date: Date
    public let coreWindowStart: Date
    public let coreWindowEnd: Date
    public let detectedStart: Date
    public let detectedEnd: Date
    public let rawIntervals: [NormalizedSleepInterval]
    public let primaryLaneIntervals: [NormalizedSleepInterval]
    /// The lane the timeline draws. Equal to `primaryLaneIntervals` unless a display filter
    /// such as `SleepPreferences.hidesBriefAwakes` is active. Never used for summaries.
    public let displayLaneIntervals: [NormalizedSleepInterval]
    public let conflicts: [TimelineConflict]
    public let summary: NightSummary
    public let hasSleepData: Bool

    /// Padding kept on each side of the detected sleep span when the timeline first opens,
    /// so the data never sits flush against the edge of the view.
    public static let detectedViewportGutter: TimeInterval = 20 * 60

    /// The window the timeline opens to: the detected sleep span padded by a gutter on each
    /// side. The configured core window acts only as a baseline the detection expands within,
    /// so an empty stretch of the configured night is never shown when the data is narrower.
    public var preferredViewportStart: Date {
        detectedStart.addingTimeInterval(-Self.detectedViewportGutter)
    }

    public var preferredViewportEnd: Date {
        detectedEnd.addingTimeInterval(Self.detectedViewportGutter)
    }

    /// Full navigable timeline. Spans the configured context and the gutter-padded detected
    /// span, so the preferred viewport always fits inside without clamping away its gutter.
    public var timelineStart: Date {
        min(coreWindowStart, preferredViewportStart)
    }

    public var timelineEnd: Date {
        max(coreWindowEnd, preferredViewportEnd)
    }

    public init(
        date: Date,
        coreWindowStart: Date,
        coreWindowEnd: Date,
        detectedStart: Date,
        detectedEnd: Date,
        rawIntervals: [NormalizedSleepInterval],
        primaryLaneIntervals: [NormalizedSleepInterval],
        displayLaneIntervals: [NormalizedSleepInterval],
        conflicts: [TimelineConflict],
        summary: NightSummary,
        hasSleepData: Bool
    ) {
        self.date = date
        self.coreWindowStart = coreWindowStart
        self.coreWindowEnd = coreWindowEnd
        self.detectedStart = detectedStart
        self.detectedEnd = detectedEnd
        self.rawIntervals = rawIntervals
        self.primaryLaneIntervals = primaryLaneIntervals
        self.displayLaneIntervals = displayLaneIntervals
        self.conflicts = conflicts
        self.summary = summary
        self.hasSleepData = hasSleepData
    }
}
