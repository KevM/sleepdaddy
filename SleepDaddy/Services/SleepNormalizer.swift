import Foundation
import HealthKit

public struct SleepNormalizer: Sendable {
    public init() {}

    public func normalize(samples: [HKCategorySample]) -> [NormalizedSleepInterval] {
        samples.map { sample in
            let stage = mapHKCategoryValue(sample.value)
            let sourceName = sample.sourceRevision.source.name
            let sourceIdentifier = sample.sourceRevision.source.bundleIdentifier
            let deviceModel = sample.device?.model
            let bundleIdentifier = sample.sourceRevision.source.bundleIdentifier

            return NormalizedSleepInterval(
                id: sample.uuid.uuidString,
                startDate: sample.startDate,
                endDate: sample.endDate,
                stage: stage,
                sourceName: sourceName,
                sourceIdentifier: sourceIdentifier,
                deviceModel: deviceModel,
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    public func mapHKCategoryValue(_ rawValue: Int) -> SleepStage {
        switch rawValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return .asleepUnspecified
        default:
            // Fallback for legacy generic asleep (value 0) or any unknown stage
            return .asleepUnspecified
        }
    }
}
