import Testing
import Foundation
@testable import SleepDaddy

struct NightAssemblerTests {
    private let assembler = NightAssembler()
    private let calendar = Calendar.current

    private var sampleDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        return calendar.date(from: components)!
    }

    @Test func testEmptyCoreWindow() {
        let prefs = SleepPreferences.default
        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: [],
            preferences: prefs
        )

        #expect(assembled.hasSleepData == false)
        #expect(assembled.rawIntervals.isEmpty)
        #expect(assembled.summary.totalSleepDuration == 0)
    }

    @Test func testEarlySleepExtensionFrom6PM() {
        let prefs = SleepPreferences.default
        let startOfDay = calendar.startOfDay(for: sampleDate)

        // 6:00 PM (18:00) on sampleDate to 2:00 AM next day
        guard let p6PM = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: startOfDay),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let a2AM = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: nextDay) else {
            Issue.record("Failed date creation")
            return
        }

        let interval = NormalizedSleepInterval(
            id: "early-1",
            startDate: p6PM,
            endDate: a2AM,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.watch"
        )

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: [interval],
            preferences: prefs
        )

        #expect(assembled.hasSleepData == true)
        #expect(assembled.detectedStart == p6PM)
    }

    @Test func testGapBelowAndAbove30Minutes() {
        let prefs = SleepPreferences.default
        let startOfDay = calendar.startOfDay(for: sampleDate)

        guard let p10PM = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: startOfDay),
              let p11PM = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: startOfDay),
              let p11_25PM = calendar.date(bySettingHour: 23, minute: 15, second: 0, of: startOfDay), // 15 min gap (< 30 min)
              let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let a7AM = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: nextDay),
              let a8AM = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: nextDay), // 60 min gap (> 30 min)
              let a8_30AM = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: nextDay) else {
            Issue.record("Failed date creation")
            return
        }

        let item1 = NormalizedSleepInterval(id: "1", startDate: p10PM, endDate: p11PM, stage: .core, sourceName: "W", sourceIdentifier: "w")
        let item2 = NormalizedSleepInterval(id: "2", startDate: p11_25PM, endDate: a7AM, stage: .deep, sourceName: "W", sourceIdentifier: "w")
        let item3 = NormalizedSleepInterval(id: "3", startDate: a8AM, endDate: a8_30AM, stage: .core, sourceName: "W", sourceIdentifier: "w")

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: [item1, item2, item3],
            preferences: prefs
        )

        #expect(assembled.hasSleepData == true)
        // item1 and item2 are contiguous because gap is 15 mins. item3 is excluded because gap after 7 AM is 60 mins (> 30 min threshold).
        #expect(assembled.rawIntervals.contains(where: { $0.id == "1" }))
        #expect(assembled.rawIntervals.contains(where: { $0.id == "2" }))
        #expect(!assembled.rawIntervals.contains(where: { $0.id == "3" }))
    }

    @Test func testDisconnectedMiddayNapExcluded() {
        let prefs = SleepPreferences.default
        let startOfDay = calendar.startOfDay(for: sampleDate)

        // Midday nap at 1:00 PM (13:00) on sampleDate
        guard let p1PM = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: startOfDay),
              let p2PM = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: startOfDay),
              let p11PM = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: startOfDay),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let a6AM = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: nextDay) else {
            Issue.record("Failed date creation")
            return
        }

        let nap = NormalizedSleepInterval(id: "nap", startDate: p1PM, endDate: p2PM, stage: .core, sourceName: "W", sourceIdentifier: "w")
        let nightSleep = NormalizedSleepInterval(id: "night", startDate: p11PM, endDate: a6AM, stage: .deep, sourceName: "W", sourceIdentifier: "w")

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: [nap, nightSleep],
            preferences: prefs
        )

        #expect(assembled.hasSleepData == true)
        #expect(assembled.rawIntervals.contains(where: { $0.id == "night" }))
        #expect(!assembled.rawIntervals.contains(where: { $0.id == "nap" }))
    }

    /// Core, a one-minute awake, then core again — all inside the default core window.
    private func laneWithBriefAwake() -> [NormalizedSleepInterval] {
        let startOfDay = calendar.startOfDay(for: sampleDate)
        let p10PM = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: startOfDay)!

        return [
            NormalizedSleepInterval(
                id: "c1",
                startDate: p10PM,
                endDate: p10PM.addingTimeInterval(3600),
                stage: .core,
                sourceName: "Watch",
                sourceIdentifier: "com.apple.watch"
            ),
            NormalizedSleepInterval(
                id: "a1",
                startDate: p10PM.addingTimeInterval(3600),
                endDate: p10PM.addingTimeInterval(3660),
                stage: .awake,
                sourceName: "Watch",
                sourceIdentifier: "com.apple.watch"
            ),
            NormalizedSleepInterval(
                id: "c2",
                startDate: p10PM.addingTimeInterval(3660),
                endDate: p10PM.addingTimeInterval(10800),
                stage: .core,
                sourceName: "Watch",
                sourceIdentifier: "com.apple.watch"
            )
        ]
    }

    @Test func testDisplayLaneMatchesPrimaryLaneWhenFilterIsOff() {
        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: laneWithBriefAwake(),
            preferences: .default
        )

        #expect(assembled.displayLaneIntervals == assembled.primaryLaneIntervals)
    }

    @Test func testBriefAwakeFilterChangesOnlyTheDisplayLane() {
        var hidingPrefs = SleepPreferences.default
        hidingPrefs.hidesBriefAwakes = true

        let intervals = laneWithBriefAwake()
        let shown = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: intervals,
            preferences: .default
        )
        let hidden = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: intervals,
            preferences: hidingPrefs
        )

        // Everything that is reported to the user is untouched.
        #expect(hidden.summary == shown.summary)
        #expect(hidden.summary.awakeDuration == 60)
        #expect(hidden.detectedStart == shown.detectedStart)
        #expect(hidden.detectedEnd == shown.detectedEnd)
        #expect(hidden.rawIntervals == shown.rawIntervals)
        #expect(hidden.primaryLaneIntervals == shown.primaryLaneIntervals)

        // Only the drawn lane loses the spike.
        #expect(hidden.displayLaneIntervals.count < hidden.primaryLaneIntervals.count)
        #expect(!hidden.displayLaneIntervals.contains { $0.stage == .awake })
        #expect(hidden.displayLaneIntervals.first?.startDate == shown.primaryLaneIntervals.first?.startDate)
        #expect(hidden.displayLaneIntervals.last?.endDate == shown.primaryLaneIntervals.last?.endDate)
    }
}
