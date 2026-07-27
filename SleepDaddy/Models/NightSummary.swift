import Foundation

public struct NightSummary: Hashable, Codable, Sendable {
    public let totalSleepDuration: TimeInterval
    public let awakeDuration: TimeInterval
    public let inBedDuration: TimeInterval
    public let stageDurations: [SleepStage: TimeInterval]
    public let conflictCount: Int

    public init(
        totalSleepDuration: TimeInterval,
        awakeDuration: TimeInterval,
        inBedDuration: TimeInterval,
        stageDurations: [SleepStage: TimeInterval],
        conflictCount: Int
    ) {
        self.totalSleepDuration = totalSleepDuration
        self.awakeDuration = awakeDuration
        self.inBedDuration = inBedDuration
        self.stageDurations = stageDurations
        self.conflictCount = conflictCount
    }

    public static let empty = NightSummary(
        totalSleepDuration: 0,
        awakeDuration: 0,
        inBedDuration: 0,
        stageDurations: [:],
        conflictCount: 0
    )
}
