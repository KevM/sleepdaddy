import Foundation

public struct NightAssembler: Sendable {
    private let awakeSpikeSmoother = AwakeSpikeSmoother()

    public init() {}

    public func assembleNight(
        for date: Date,
        allNormalizedIntervals: [NormalizedSleepInterval],
        preferences: SleepPreferences
    ) -> AssembledNight {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        // Core window calculation
        guard let coreWindowStart = calendar.date(bySettingHour: preferences.coreWindowStartHour, minute: 0, second: 0, of: startOfDay),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let coreWindowEnd = calendar.date(bySettingHour: preferences.coreWindowEndHour, minute: 0, second: 0, of: nextDay) else {
            let now = Date()
            return AssembledNight(
                date: date,
                coreWindowStart: now,
                coreWindowEnd: now,
                detectedStart: now,
                detectedEnd: now,
                rawIntervals: [],
                primaryLaneIntervals: [],
                displayLaneIntervals: [],
                conflicts: [],
                summary: .empty,
                hasSleepData: false
            )
        }

        // 4-hour safety buffer caps
        let safetyCapStart = coreWindowStart.addingTimeInterval(-4 * 3600)
        let safetyCapEnd = coreWindowEnd.addingTimeInterval(4 * 3600)

        // Step 1 & 2: Filter by source selection and local sample exclusions
        let selectedSet = Set(preferences.selectedSourceIdentifiers)
        let eligibleIntervals = allNormalizedIntervals.filter { interval in
            if preferences.excludedSampleIDs.contains(interval.id) {
                return false
            }
            if !selectedSet.isEmpty {
                return selectedSet.contains(interval.sourceIdentifier)
            }
            return true
        }

        // Candidates within safety window
        let candidatesInSafetyBuffer = eligibleIntervals.filter { interval in
            interval.endDate > safetyCapStart && interval.startDate < safetyCapEnd
        }

        // Seed set: records overlapping the core window
        let seedIntervals = candidatesInSafetyBuffer.filter { interval in
            interval.endDate > coreWindowStart && interval.startDate < coreWindowEnd
        }

        if seedIntervals.isEmpty {
            return AssembledNight(
                date: date,
                coreWindowStart: coreWindowStart,
                coreWindowEnd: coreWindowEnd,
                detectedStart: coreWindowStart,
                detectedEnd: coreWindowEnd,
                rawIntervals: [],
                primaryLaneIntervals: [],
                displayLaneIntervals: [],
                conflicts: [],
                summary: .empty,
                hasSleepData: false
            )
        }

        // Step 3 & 4: Contiguous expansion with max 30 min (1800s) gap
        var activeSet = Set(seedIntervals)
        var minStart = seedIntervals.map { $0.startDate }.min() ?? coreWindowStart
        var maxEnd = seedIntervals.map { $0.endDate }.max() ?? coreWindowEnd

        // Backward expansion
        var addedNew = true
        while addedNew && minStart > safetyCapStart {
            addedNew = false
            for candidate in candidatesInSafetyBuffer where !activeSet.contains(candidate) {
                // Check if candidate ends after safetyCapStart and within 30 mins (1800s) of current minStart
                if candidate.endDate >= safetyCapStart {
                    let gap = minStart.timeIntervalSince(candidate.endDate)
                    if gap <= 1800 && candidate.startDate < minStart {
                        activeSet.insert(candidate)
                        minStart = min(minStart, candidate.startDate)
                        addedNew = true
                    }
                }
            }
        }

        // Forward expansion
        addedNew = true
        while addedNew && maxEnd < safetyCapEnd {
            addedNew = false
            for candidate in candidatesInSafetyBuffer where !activeSet.contains(candidate) {
                if candidate.startDate <= safetyCapEnd {
                    let gap = candidate.startDate.timeIntervalSince(maxEnd)
                    if gap <= 1800 && candidate.endDate > maxEnd {
                        activeSet.insert(candidate)
                        maxEnd = max(maxEnd, candidate.endDate)
                        addedNew = true
                    }
                }
            }
        }

        let detectedStart = max(safetyCapStart, minStart)
        let detectedEnd = min(safetyCapEnd, maxEnd)

        let assembledRawIntervals = Array(activeSet).sorted { $0.startDate < $1.startDate }

        // Primary visual lane resolution & conflict detection
        let (primaryLane, conflicts) = resolvePrimaryLaneAndConflicts(
            intervals: assembledRawIntervals,
            sourceSelectionOrder: preferences.selectedSourceIdentifiers,
            detectedStart: detectedStart,
            detectedEnd: detectedEnd
        )

        // Summary calculation
        let summary = calculateSummary(primaryLane: primaryLane, conflicts: conflicts, detectedStart: detectedStart, detectedEnd: detectedEnd)

        // Runs after the summary so a hidden spike can never reach a reported total.
        let displayLane = preferences.hidesBriefAwakes
            ? awakeSpikeSmoother.smooth(lane: primaryLane)
            : primaryLane

        return AssembledNight(
            date: date,
            coreWindowStart: coreWindowStart,
            coreWindowEnd: coreWindowEnd,
            detectedStart: detectedStart,
            detectedEnd: detectedEnd,
            rawIntervals: assembledRawIntervals,
            primaryLaneIntervals: primaryLane,
            displayLaneIntervals: displayLane,
            conflicts: conflicts,
            summary: summary,
            hasSleepData: true
        )
    }

    private func resolvePrimaryLaneAndConflicts(
        intervals: [NormalizedSleepInterval],
        sourceSelectionOrder: [String],
        detectedStart: Date,
        detectedEnd: Date
    ) -> ([NormalizedSleepInterval], [TimelineConflict]) {
        guard !intervals.isEmpty else { return ([], []) }

        // Collect all distinct time boundaries
        var timeBoundaries = Set<Date>()
        for interval in intervals {
            let clampedStart = max(detectedStart, interval.startDate)
            let clampedEnd = min(detectedEnd, interval.endDate)
            if clampedStart < clampedEnd {
                timeBoundaries.insert(clampedStart)
                timeBoundaries.insert(clampedEnd)
            }
        }

        let sortedBoundaries = timeBoundaries.sorted()
        guard sortedBoundaries.count >= 2 else { return ([], []) }

        var laneSlices: [(Date, Date, SleepStage, NormalizedSleepInterval)] = []
        var rawConflicts: [TimelineConflict] = []

        let sourceRankMap = Dictionary(uniqueKeysWithValues: sourceSelectionOrder.enumerated().map { ($1, $0) })

        for i in 0..<(sortedBoundaries.count - 1) {
            let sliceStart = sortedBoundaries[i]
            let sliceEnd = sortedBoundaries[i + 1]
            let sliceMid = sliceStart.addingTimeInterval((sliceEnd.timeIntervalSince(sliceStart)) / 2.0)

            let covering = intervals.filter { $0.startDate <= sliceMid && $0.endDate >= sliceMid }
            guard !covering.isEmpty else { continue }

            // Check conflicts across distinct sources with differing stages
            let distinctSources = Set(covering.map { $0.sourceIdentifier })
            let distinctStages = Set(covering.map { $0.stage })
            if distinctSources.count > 1 && distinctStages.count > 1 {
                // Determine winning stage for slice
                let winner = selectWinningInterval(covering: covering, sourceRankMap: sourceRankMap)
                rawConflicts.append(TimelineConflict(
                    startDate: sliceStart,
                    endDate: sliceEnd,
                    conflictingIntervals: covering,
                    resolvedStage: winner.stage
                ))
            }

            let winner = selectWinningInterval(covering: covering, sourceRankMap: sourceRankMap)
            laneSlices.append((sliceStart, sliceEnd, winner.stage, winner))
        }

        // Coalesce continuous slices with same stage and source
        var primaryLane: [NormalizedSleepInterval] = []
        for slice in laneSlices {
            if let last = primaryLane.last, last.stage == slice.2 && last.sourceIdentifier == slice.3.sourceIdentifier && last.endDate == slice.0 {
                // Extend last interval
                let updated = NormalizedSleepInterval(
                    id: last.id,
                    startDate: last.startDate,
                    endDate: slice.1,
                    stage: last.stage,
                    sourceName: last.sourceName,
                    sourceIdentifier: last.sourceIdentifier,
                    deviceModel: last.deviceModel,
                    bundleIdentifier: last.bundleIdentifier
                )
                primaryLane[primaryLane.count - 1] = updated
            } else {
                let uniqueID = "\(slice.3.id)-\(Int(slice.0.timeIntervalSince1970))"
                let newInterval = NormalizedSleepInterval(
                    id: uniqueID,
                    startDate: slice.0,
                    endDate: slice.1,
                    stage: slice.2,
                    sourceName: slice.3.sourceName,
                    sourceIdentifier: slice.3.sourceIdentifier,
                    deviceModel: slice.3.deviceModel,
                    bundleIdentifier: slice.3.bundleIdentifier
                )
                primaryLane.append(newInterval)
            }
        }

        // Merge contiguous conflict slices
        let mergedConflicts = mergeContiguousConflicts(rawConflicts)

        return (primaryLane, mergedConflicts)
    }

    private func selectWinningInterval(
        covering: [NormalizedSleepInterval],
        sourceRankMap: [String: Int]
    ) -> NormalizedSleepInterval {
        covering.min { a, b in
            // Rule 1 & 2: Specificity rank (higher is better)
            if a.stage.specificityRank != b.stage.specificityRank {
                return a.stage.specificityRank > b.stage.specificityRank
            }
            // Rule 3: Source ordering tiebreaker (lower rank index is better)
            let rankA = sourceRankMap[a.sourceIdentifier] ?? Int.max
            let rankB = sourceRankMap[b.sourceIdentifier] ?? Int.max
            if rankA != rankB {
                return rankA < rankB
            }
            // Fallback: Stable string comparison on source Identifier or sample ID
            if a.sourceIdentifier != b.sourceIdentifier {
                return a.sourceIdentifier < b.sourceIdentifier
            }
            return a.id < b.id
        }!
    }

    private func mergeContiguousConflicts(_ conflicts: [TimelineConflict]) -> [TimelineConflict] {
        guard !conflicts.isEmpty else { return [] }

        var result: [TimelineConflict] = []
        for conflict in conflicts {
            if let last = result.last, last.endDate == conflict.startDate && Set(last.conflictingIntervals.map { $0.id }) == Set(conflict.conflictingIntervals.map { $0.id }) {
                let updated = TimelineConflict(
                    startDate: last.startDate,
                    endDate: conflict.endDate,
                    conflictingIntervals: last.conflictingIntervals,
                    resolvedStage: last.resolvedStage
                )
                result[result.count - 1] = updated
            } else {
                result.append(conflict)
            }
        }
        return result
    }

    private func calculateSummary(
        primaryLane: [NormalizedSleepInterval],
        conflicts: [TimelineConflict],
        detectedStart: Date,
        detectedEnd: Date
    ) -> NightSummary {
        var stageDurations: [SleepStage: TimeInterval] = [:]
        var totalSleep: TimeInterval = 0
        var awake: TimeInterval = 0
        var inBed: TimeInterval = 0

        for interval in primaryLane {
            let dur = interval.duration
            stageDurations[interval.stage, default: 0] += dur

            if interval.stage.isSleep {
                totalSleep += dur
            } else if interval.stage == .awake {
                awake += dur
            } else if interval.stage == .inBed {
                inBed += dur
            }
        }

        return NightSummary(
            totalSleepDuration: totalSleep,
            awakeDuration: awake,
            inBedDuration: inBed,
            stageDurations: stageDurations,
            conflictCount: conflicts.count
        )
    }
}
