import Foundation

public struct TimelineConflict: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(startDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)" }
    public let startDate: Date
    public let endDate: Date
    public let conflictingIntervals: [NormalizedSleepInterval]
    public let resolvedStage: SleepStage

    public init(
        startDate: Date,
        endDate: Date,
        conflictingIntervals: [NormalizedSleepInterval],
        resolvedStage: SleepStage
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.conflictingIntervals = conflictingIntervals
        self.resolvedStage = resolvedStage
    }

    public var sourceNames: [String] {
        Array(Set(conflictingIntervals.map { $0.sourceName })).sorted()
    }
}
