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

    public var isExtended: Bool {
        detectedStart < coreWindowStart || detectedEnd > coreWindowEnd
    }

    /// Full navigable timeline, including both configured context and any detected extension.
    public var timelineStart: Date {
        min(coreWindowStart, detectedStart)
    }

    public var timelineEnd: Date {
        max(coreWindowEnd, detectedEnd)
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
