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

        var mutableLane = lane
        var result: [NormalizedSleepInterval] = []
        var i = 0
        let n = mutableLane.count

        while i < n {
            let current = mutableLane[i]

            if !isBriefAwake(current) {
                result.append(current)
                i += 1
                continue
            }

            // Gather contiguous brief awakes that touch each other
            var briefChain: [NormalizedSleepInterval] = [current]
            var j = i + 1
            while j < n && isBriefAwake(mutableLane[j]) && touches(mutableLane[j - 1], mutableLane[j]) {
                briefChain.append(mutableLane[j])
                j += 1
            }

            let chainStart = briefChain.first!.startDate
            let chainEnd = briefChain.last!.endDate

            if let last = result.last, touches(last.endDate, chainStart) {
                // Absorb forward into preceding interval if it touches the spike chain
                result[result.count - 1] = last.copy(endDate: max(last.endDate, chainEnd))
            } else if j < n && !isBriefAwake(mutableLane[j]) && touches(chainEnd, mutableLane[j].startDate) {
                // Absorb backward into following non-brief interval if it touches the spike chain
                let following = mutableLane[j]
                mutableLane[j] = following.copy(startDate: min(chainStart, following.startDate))
            } else {
                // Neither neighbor touches the spike chain; preserve the spike(s)
                result.append(contentsOf: briefChain)
            }

            i = j
        }

        return coalesced(result)
    }

    private func isBriefAwake(_ interval: NormalizedSleepInterval) -> Bool {
        interval.stage == .awake && interval.duration <= Self.briefAwakeThreshold
    }

    private func touches(_ aEnd: Date, _ bStart: Date) -> Bool {
        abs(bStart.timeIntervalSince(aEnd)) < 0.001
    }

    private func touches(_ a: NormalizedSleepInterval, _ b: NormalizedSleepInterval) -> Bool {
        touches(a.endDate, b.startDate)
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
