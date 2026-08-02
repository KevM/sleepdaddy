import Foundation

public struct NormalizedSleepInterval: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startDate: Date
    public let endDate: Date
    public let stage: SleepStage
    public let sourceName: String
    public let sourceIdentifier: String
    public let deviceModel: String?
    public let bundleIdentifier: String?

    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    public init(
        id: String,
        startDate: Date,
        endDate: Date,
        stage: SleepStage,
        sourceName: String,
        sourceIdentifier: String,
        deviceModel: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.stage = stage
        self.sourceName = sourceName
        self.sourceIdentifier = sourceIdentifier
        self.deviceModel = deviceModel
        self.bundleIdentifier = bundleIdentifier
    }

    public var accessibilityDescription: String {
        let timeRange = AccessibilityHelpers.formattedTimeRange(start: startDate, end: endDate)

        let durationMinutes = Int(round(duration / 60.0))
        return "\(stage.displayName), \(timeRange) (\(durationMinutes) min), from \(sourceName)"
    }
}
