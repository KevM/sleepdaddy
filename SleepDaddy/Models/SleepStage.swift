import SwiftUI

public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case awake
    case rem
    case core
    case deep
    case asleepUnspecified
    case inBed

    public var displayName: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .core: return "Core"
        case .deep: return "Deep"
        case .asleepUnspecified: return "Asleep (Unspecified)"
        case .inBed: return "In Bed"
        }
    }

    public var shortLabel: String {
        switch self {
        case .awake: return "AWK"
        case .rem: return "REM"
        case .core: return "COR"
        case .deep: return "DEP"
        case .asleepUnspecified: return "SLP"
        case .inBed: return "BED"
        }
    }

    public var isSleep: Bool {
        switch self {
        case .rem, .core, .deep, .asleepUnspecified:
            return true
        case .awake, .inBed:
            return false
        }
    }

    /// Specificity priority for conflict resolution:
    /// Higher score means higher specificity.
    /// Detailed stages (awake, rem, core, deep) = 2
    /// Asleep unspecified = 1
    /// In bed = 0
    public var specificityRank: Int {
        switch self {
        case .awake, .rem, .core, .deep:
            return 2
        case .asleepUnspecified:
            return 1
        case .inBed:
            return 0
        }
    }

    /// Row order index for vertical lane layout in timeline view (0 top, N bottom)
    public var rowIndex: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .core: return 2
        case .deep: return 3
        case .asleepUnspecified: return 4
        case .inBed: return 5
        }
    }

    public var themeColor: Color {
        switch self {
        case .awake:
            return Color(red: 0.95, green: 0.45, blue: 0.40) // Coral / Warm orange
        case .rem:
            return Color(red: 0.40, green: 0.70, blue: 0.95) // Cyan / Light Blue
        case .core:
            return Color(red: 0.25, green: 0.50, blue: 0.85) // Medium Blue
        case .deep:
            return Color(red: 0.15, green: 0.25, blue: 0.65) // Dark Indigo
        case .asleepUnspecified:
            return Color(red: 0.50, green: 0.40, blue: 0.80) // Muted Violet
        case .inBed:
            return Color(red: 0.45, green: 0.45, blue: 0.50) // Slate Gray
        }
    }
}
