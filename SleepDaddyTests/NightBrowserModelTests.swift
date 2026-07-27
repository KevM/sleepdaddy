import Testing
import Foundation
@testable import SleepDaddy

struct NightBrowserModelTests {
    @Test @MainActor func testModelInitializationAndDataLoading() async {
        let fixtureStore = FixtureSleepStore()
        let testDefaults = UserDefaults(suiteName: "NightBrowserModelTests")!
        testDefaults.removePersistentDomain(forName: "NightBrowserModelTests")
        let prefsStore = PreferencesStore(userDefaults: testDefaults)

        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore)

        await model.loadData()

        #expect(model.appState == .loaded)
        #expect(model.assembledNights.count == 14) // 14 nights overview strip
        #expect(!model.availableSources.isEmpty)
    }

    @Test @MainActor func testExcludingAndRestoringRecord() async {
        let fixtureStore = FixtureSleepStore()
        let testDefaults = UserDefaults(suiteName: "NightBrowserModelTests2")!
        testDefaults.removePersistentDomain(forName: "NightBrowserModelTests2")
        let prefsStore = PreferencesStore(userDefaults: testDefaults)

        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore)
        await model.loadData()

        guard let night = model.selectedAssembledNight,
              let firstItem = night.rawIntervals.first else {
            Issue.record("No fixture interval found")
            return
        }

        let targetItem = firstItem
        model.excludeSample(targetItem)

        #expect(model.preferences.excludedSampleIDs.contains(targetItem.id))
        #expect(model.excludedRecordDetails[targetItem.id]?.id == targetItem.id)

        if let updatedNight = model.selectedAssembledNight {
            #expect(!updatedNight.rawIntervals.contains(where: { $0.id == targetItem.id }))
        }

        model.restoreSample(id: targetItem.id)
        #expect(!model.preferences.excludedSampleIDs.contains(targetItem.id))
        #expect(model.excludedRecordDetails[targetItem.id] == nil)
    }

    private static let testCalendar = Calendar.current

    private static var july25Noon: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 25
        comps.hour = 12
        comps.minute = 0
        return testCalendar.date(from: comps)!
    }

    private static var july24Date: Date {
        testCalendar.date(byAdding: .day, value: -1, to: july25Noon)!
    }

    private static var july20Date: Date {
        testCalendar.date(byAdding: .day, value: -5, to: july25Noon)!
    }

    private func makeTestModel(
        now: @escaping @Sendable () -> Date,
        intervals: [NormalizedSleepInterval]? = nil
    ) -> NightBrowserModel {
        let fixtureStore = FixtureSleepStore(customIntervals: intervals)
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefsStore = PreferencesStore(userDefaults: testDefaults)
        return NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore, now: now)
    }

    @Test @MainActor func loadSelectsNewestPopulatedNight() async {
        let olderInterval = NormalizedSleepInterval(
            id: "older-1",
            startDate: Self.testCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: Self.july20Date)!,
            endDate: Self.testCalendar.date(bySettingHour: 7, minute: 0, second: 0, of: Self.testCalendar.date(byAdding: .day, value: 1, to: Self.july20Date)!)!,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health",
            deviceModel: nil,
            bundleIdentifier: nil
        )

        let previousInterval = NormalizedSleepInterval(
            id: "prev-1",
            startDate: Self.testCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: Self.july24Date)!,
            endDate: Self.testCalendar.date(bySettingHour: 7, minute: 0, second: 0, of: Self.july25Noon)!,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health",
            deviceModel: nil,
            bundleIdentifier: nil
        )

        let model = makeTestModel(
            now: { Self.july25Noon },
            intervals: [olderInterval, previousInterval]
        )
        await model.loadData()

        #expect(Self.testCalendar.isDate(model.selectedDate, inSameDayAs: Self.july24Date))
    }

    @Test @MainActor func fullNightViewportIncludesConfiguredNightWindow() async {
        let sleepStart = Self.testCalendar.date(
            bySettingHour: 23,
            minute: 0,
            second: 0,
            of: Self.july24Date
        )!
        let sleepEnd = Self.testCalendar.date(
            bySettingHour: 6,
            minute: 0,
            second: 0,
            of: Self.july25Noon
        )!
        let interval = NormalizedSleepInterval(
            id: "inside-core-window",
            startDate: sleepStart,
            endDate: sleepEnd,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health"
        )
        let model = makeTestModel(
            now: { Self.july25Noon },
            intervals: [interval]
        )

        await model.loadData()

        let expectedStart = Self.testCalendar.date(
            bySettingHour: 19,
            minute: 0,
            second: 0,
            of: Self.july24Date
        )!
        let expectedEnd = Self.testCalendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: Self.july25Noon
        )!
        #expect(model.viewportStart == expectedStart)
        #expect(model.viewportEnd == expectedEnd)
    }

    @Test @MainActor func loadSelectsYesterdayWhenNoData() async {
        let model = makeTestModel(
            now: { Self.july25Noon },
            intervals: []
        )
        await model.loadData()

        #expect(Self.testCalendar.isDate(model.selectedDate, inSameDayAs: Self.july24Date))
    }

    @Test @MainActor func adjacentNavigationStopsAtBounds() async {
        let model = makeTestModel(now: { Self.july25Noon })
        await model.loadData()

        #expect(model.canSelectPreviousNight)
        while model.canSelectPreviousNight {
            model.selectPreviousNight()
        }
        let oldest = model.selectedDate
        model.selectPreviousNight()
        #expect(model.selectedDate == oldest)

        #expect(model.canSelectNextNight)
        while model.canSelectNextNight {
            model.selectNextNight()
        }
        let newest = model.selectedDate
        model.selectNextNight()
        #expect(model.selectedDate == newest)
    }
}
