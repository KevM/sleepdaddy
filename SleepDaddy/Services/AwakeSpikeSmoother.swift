import Foundation

/// Removes very short awake intervals from a lane without changing the span the lane covers.
///
/// This exists for drawing only. Night summaries are computed from the unsmoothed lane, so
/// hiding a spike here never changes a reported total.
public struct AwakeSpikeSmoother: Sendable {
    /// An awake interval of this duration or shorter is treated as a spike and hidden.
    public static let briefAwakeThreshold: TimeInterval = 60

    public init() {}

    /// - Parameter lane: intervals sorted by `startDate`, as produced by `NightAssembler`.
    /// - Returns: the lane with brief awake intervals removed, their time given to the
    ///   neighbouring interval so the lane stays gap-free.
    public func smooth(lane: [NormalizedSleepInterval]) -> [NormalizedSleepInterval] {
        // Nothing to hide, or nothing left if we did: return the input untouched. The second
        // case is a night recorded as brief awakes and nothing else, where smoothing would
        // empty the timeline while the summary still reported awake time.
        guard lane.contains(where: isBriefAwake) else { return lane }
        guard lane.contains(where: { !isBriefAwake($0) }) else { return lane }

        var kept: [NormalizedSleepInterval] = []
        var pendingHeadStart: Date?

        for interval in lane {
            guard isBriefAwake(interval) else {
                var next = interval
                if let headStart = pendingHeadStart {
                    next = next.copy(startDate: min(headStart, next.startDate))
                    pendingHeadStart = nil
                }
                kept.append(next)
                continue
            }

            if let last = kept.last {
                kept[kept.count - 1] = last.copy(endDate: max(last.endDate, interval.endDate))
            } else {
                // A spike opening the lane has nothing behind it, so the first interval that
                // survives will reach back over it instead.
                pendingHeadStart = min(pendingHeadStart ?? interval.startDate, interval.startDate)
            }
        }

        return coalesced(kept)
    }

    private func isBriefAwake(_ interval: NormalizedSleepInterval) -> Bool {
        interval.stage == .awake && interval.duration <= Self.briefAwakeThreshold
    }

    /// Merges neighbours that now touch and agree on stage and source, matching the rule the
    /// assembler uses when it builds the primary lane.
    private func coalesced(_ intervals: [NormalizedSleepInterval]) -> [NormalizedSleepInterval] {
        var result: [NormalizedSleepInterval] = []

        for interval in intervals {
            if let last = result.last,
               last.stage == interval.stage,
               last.sourceIdentifier == interval.sourceIdentifier,
               abs(interval.startDate.timeIntervalSince(last.endDate)) < 0.001 {
                result[result.count - 1] = last.copy(endDate: max(last.endDate, interval.endDate))
            } else {
                result.append(interval)
            }
        }

        return result
    }
}

private extension NormalizedSleepInterval {
    /// `NormalizedSleepInterval` is immutable, so widening one means rebuilding it. The
    /// identity of the absorbing interval is kept so lane IDs stay resolvable.
    func copy(startDate: Date? = nil, endDate: Date? = nil) -> NormalizedSleepInterval {
        NormalizedSleepInterval(
            id: id,
            startDate: startDate ?? self.startDate,
            endDate: endDate ?? self.endDate,
            stage: stage,
            sourceName: sourceName,
            sourceIdentifier: sourceIdentifier,
            deviceModel: deviceModel,
            bundleIdentifier: bundleIdentifier
        )
    }
}
