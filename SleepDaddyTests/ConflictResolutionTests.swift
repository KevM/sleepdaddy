import Testing
import Foundation
@testable import SleepDaddy

struct ConflictResolutionTests {
    private let assembler = NightAssembler()
    private let calendar = Calendar.current

    private var sampleDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        return calendar.date(from: components)!
    }

    @Test func testSpecificityResolutionOverInBedAndUnspecified() {
        let startOfDay = calendar.startOfDay(for: sampleDate)

        guard let p11PM = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: startOfDay),
              let p11_30PM = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: startOfDay) else {
            Issue.record("Failed date creation")
            return
        }

        let inBedItem = NormalizedSleepInterval(id: "inbed", startDate: p11PM, endDate: p11_30PM, stage: .inBed, sourceName: "App A", sourceIdentifier: "com.appa")
        let unspecifiedItem = NormalizedSleepInterval(id: "unspec", startDate: p11PM, endDate: p11_30PM, stage: .asleepUnspecified, sourceName: "App B", sourceIdentifier: "com.appb")
        let deepItem = NormalizedSleepInterval(id: "deep", startDate: p11PM, endDate: p11_30PM, stage: .deep, sourceName: "App C", sourceIdentifier: "com.appc")

        var prefs = SleepPreferences.default
        prefs.selectedSourceIdentifiers = ["com.appa", "com.appb", "com.appc"]

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: [inBedItem, unspecifiedItem, deepItem],
            preferences: prefs
        )

        #expect(assembled.primaryLaneIntervals.count == 1)
        #expect(assembled.primaryLaneIntervals.first?.stage == .deep)
        #expect(assembled.conflicts.count > 0)
    }

    @Test func testSourceOrderingTiebreaker() {
        let startOfDay = calendar.startOfDay(for: sampleDate)

        guard let p11PM = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: startOfDay),
              let p11_30PM = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: startOfDay) else {
            Issue.record("Failed date creation")
            return
        }

        let itemA = NormalizedSleepInterval(id: "a", startDate: p11PM, endDate: p11_30PM, stage: .rem, sourceName: "Source 1", sourceIdentifier: "com.source1")
        let itemB = NormalizedSleepInterval(id: "b", startDate: p11PM, endDate: p11_30PM, stage: .core, sourceName: "Source 2", sourceIdentifier: "com.source2")

        // Preference order puts com.source2 first
        var prefs = SleepPreferences.default
        prefs.selectedSourceIdentifiers = ["com.source2", "com.source1"]

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: [itemA, itemB],
            preferences: prefs
        )

        #expect(assembled.primaryLaneIntervals.first?.stage == .core)
        #expect(assembled.primaryLaneIntervals.first?.sourceIdentifier == "com.source2")
    }
}
