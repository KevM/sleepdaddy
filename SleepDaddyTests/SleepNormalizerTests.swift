import Testing
import Foundation
import HealthKit
@testable import SleepDaddy

struct SleepNormalizerTests {
    @Test func testCategoryValueMapping() {
        let normalizer = SleepNormalizer()

        #expect(normalizer.mapHKCategoryValue(HKCategoryValueSleepAnalysis.inBed.rawValue) == .inBed)
        #expect(normalizer.mapHKCategoryValue(HKCategoryValueSleepAnalysis.awake.rawValue) == .awake)
        #expect(normalizer.mapHKCategoryValue(HKCategoryValueSleepAnalysis.asleepCore.rawValue) == .core)
        #expect(normalizer.mapHKCategoryValue(HKCategoryValueSleepAnalysis.asleepDeep.rawValue) == .deep)
        #expect(normalizer.mapHKCategoryValue(HKCategoryValueSleepAnalysis.asleepREM.rawValue) == .rem)
        #expect(normalizer.mapHKCategoryValue(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue) == .asleepUnspecified)
        #expect(normalizer.mapHKCategoryValue(99) == .asleepUnspecified) // Unknown value fallback
    }

    @Test func testNormalizedIntervalProperties() {
        let now = Date()
        let interval = NormalizedSleepInterval(
            id: "test-id-123",
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            stage: .deep,
            sourceName: "Apple Watch",
            sourceIdentifier: "com.apple.health",
            deviceModel: "Watch7,1",
            bundleIdentifier: "com.apple.health"
        )

        #expect(interval.id == "test-id-123")
        #expect(interval.duration == 3600)
        #expect(interval.stage == .deep)
        #expect(interval.sourceName == "Apple Watch")
        #expect(interval.accessibilityDescription.contains("Deep"))
    }
}
