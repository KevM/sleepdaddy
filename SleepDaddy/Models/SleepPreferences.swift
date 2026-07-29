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
    /// Hides awake intervals of one minute or less from the timeline drawing.
    /// Night summaries are computed from the unfiltered lane and are unaffected.
    public var hidesBriefAwakes: Bool

    public init(
        coreWindowStartHour: Int = 19,
        coreWindowEndHour: Int = 7,
        selectedSourceIdentifiers: [String] = [],
        excludedSampleIDs: Set<String> = [],
        hidesBriefAwakes: Bool = false
    ) {
        self.coreWindowStartHour = coreWindowStartHour
        self.coreWindowEndHour = coreWindowEndHour
        self.selectedSourceIdentifiers = selectedSourceIdentifiers
        self.excludedSampleIDs = excludedSampleIDs
        self.hidesBriefAwakes = hidesBriefAwakes
    }

    /// Decoding is written out rather than synthesized so that preferences saved before a
    /// property existed still load. Synthesized decoding treats a missing key as an error and
    /// ignores the default value, and `PreferencesStore.load()` turns any error into
    /// `.default` — which would discard the stored window, sources, and exclusions on upgrade.
    /// Any property added here in future must use `decodeIfPresent` for the same reason.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.coreWindowStartHour = try container.decode(Int.self, forKey: .coreWindowStartHour)
        self.coreWindowEndHour = try container.decode(Int.self, forKey: .coreWindowEndHour)
        self.selectedSourceIdentifiers = try container.decode([String].self, forKey: .selectedSourceIdentifiers)
        self.excludedSampleIDs = try container.decode(Set<String>.self, forKey: .excludedSampleIDs)
        self.hidesBriefAwakes = try container.decodeIfPresent(Bool.self, forKey: .hidesBriefAwakes) ?? false
    }

    public static let `default` = SleepPreferences()
}
