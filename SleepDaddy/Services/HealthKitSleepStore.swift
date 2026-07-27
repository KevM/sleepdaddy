import Foundation
import HealthKit

public protocol HealthKitSleepStoreProtocol: Sendable {
    func requestAuthorization() async throws -> Bool
    func fetchSleepSamples(start: Date, end: Date) async throws -> [NormalizedSleepInterval]
}

public final class HealthKitSleepStore: HealthKitSleepStoreProtocol, @unchecked Sendable {
    private let healthStore = HKHealthStore()

    public init() {}

    public func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return false
        }

        try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
        return true
    }

    public func fetchSleepSamples(start: Date, end: Date) async throws -> [NormalizedSleepInterval] {
        guard HKHealthStore.isHealthDataAvailable() else {
            return []
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let normalizer = SleepNormalizer()
                let normalized = normalizer.normalize(samples: categorySamples)
                continuation.resume(returning: normalized)
            }

            self.healthStore.execute(query)
        }
    }
}
