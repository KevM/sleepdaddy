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

    /// The span of pulse-oximeter data attached to this night, when any exists.
    ///
    /// Set by `NightBrowserModel` after assembly, never by `NightAssembler` — vitals have
    /// nothing to do with grouping sleep intervals, and threading a store through the
    /// assembler would join two unrelated concerns.
    public let vitalsExtent: DateInterval?

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

    /// Full navigable timeline, defined by **data** rather than by the configured core
    /// window. The gutter-padded detected span is the floor, widened by any vitals
    /// recording that extends beyond it.
    ///
    /// The core window no longer participates. It keeps its other responsibility — seeding
    /// which intervals belong to a night in `NightAssembler` — unchanged. A night with
    /// sleep from 23:00 to 06:00 previously allowed panning back to 19:00 across empty
    /// evening; it now bounds to the data.
    public var timelineStart: Date {
        guard let vitalsExtent else { return preferredViewportStart }
        return min(preferredViewportStart, vitalsExtent.start)
    }

    public var timelineEnd: Date {
        guard let vitalsExtent else { return preferredViewportEnd }
        return max(preferredViewportEnd, vitalsExtent.end)
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
        hasSleepData: Bool,
        vitalsExtent: DateInterval? = nil
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
        self.vitalsExtent = vitalsExtent
    }

    /// Returns a copy carrying `extent`. Used by `NightBrowserModel` to attach vitals
    /// without `NightAssembler` knowing they exist.
    public func withVitalsExtent(_ extent: DateInterval?) -> AssembledNight {
        AssembledNight(
            date: date,
            coreWindowStart: coreWindowStart,
            coreWindowEnd: coreWindowEnd,
            detectedStart: detectedStart,
            detectedEnd: detectedEnd,
            rawIntervals: rawIntervals,
            primaryLaneIntervals: primaryLaneIntervals,
            displayLaneIntervals: displayLaneIntervals,
            conflicts: conflicts,
            summary: summary,
            hasSleepData: hasSleepData,
            vitalsExtent: extent
        )
    }
}
