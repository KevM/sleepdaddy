import Foundation

public struct SleepPreferences: Equatable, Codable, Sendable {
    /// Default core window start hour (7:00 PM / 19:00)
    public var coreWindowStartHour: Int
    /// Default core window end hour (7:00 AM / 07:00 next day)
    public var coreWindowEndHour: Int
    /// Ordered list of selected HealthKit source identifiers. If empty, all sources are active by default.
    public var selectedSourceIdentifiers: [String]
    /// Set of locally excluded HealthKit sample IDs
    public var excludedSampleIDs: Set<String>

    public init(
        coreWindowStartHour: Int = 19,
        coreWindowEndHour: Int = 7,
        selectedSourceIdentifiers: [String] = [],
        excludedSampleIDs: Set<String> = []
    ) {
        self.coreWindowStartHour = coreWindowStartHour
        self.coreWindowEndHour = coreWindowEndHour
        self.selectedSourceIdentifiers = selectedSourceIdentifiers
        self.excludedSampleIDs = excludedSampleIDs
    }

    public static let `default` = SleepPreferences()
}
