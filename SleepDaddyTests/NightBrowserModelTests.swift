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
        makeTestModelAndStore(now: now, intervals: intervals).model
    }

    private func makeTestModelAndStore(
        now: @escaping @Sendable () -> Date,
        intervals: [NormalizedSleepInterval]? = nil
    ) -> (model: NightBrowserModel, store: FixtureSleepStore) {
        let fixtureStore = FixtureSleepStore(customIntervals: intervals)
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefsStore = PreferencesStore(userDefaults: testDefaults)
        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore, now: now)
        return (model, fixtureStore)
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

    @Test @MainActor func sceneActivationLoadsNewSleepDataWithoutChangingSelection() async {
        let olderInterval = NormalizedSleepInterval(
            id: "older-foreground-refresh",
            startDate: Self.testCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: Self.july20Date)!,
            endDate: Self.testCalendar.date(
                bySettingHour: 7,
                minute: 0,
                second: 0,
                of: Self.testCalendar.date(byAdding: .day, value: 1, to: Self.july20Date)!
            )!,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health"
        )
        let newerInterval = NormalizedSleepInterval(
            id: "newer-foreground-refresh",
            startDate: Self.testCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: Self.july24Date)!,
            endDate: Self.testCalendar.date(bySettingHour: 7, minute: 0, second: 0, of: Self.july25Noon)!,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health"
        )
        let (model, fixtureStore) = makeTestModelAndStore(
            now: { Self.july25Noon },
            intervals: [olderInterval]
        )
        await model.loadData()
        #expect(Self.testCalendar.isDate(model.selectedDate, inSameDayAs: Self.july20Date))

        fixtureStore.customIntervals = [olderInterval, newerInterval]
        await model.handleScenePhaseChange(.active)

        #expect(Self.testCalendar.isDate(model.selectedDate, inSameDayAs: Self.july20Date))
        #expect(model.assembledNights.contains { night in
            night.rawIntervals.contains { $0.id == newerInterval.id }
        })
    }

    @Test @MainActor func sceneActivationPreservesNavigationState() async {
        let olderInterval = NormalizedSleepInterval(
            id: "selected-before-refresh",
            startDate: Self.testCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: Self.july20Date)!,
            endDate: Self.testCalendar.date(
                bySettingHour: 7,
                minute: 0,
                second: 0,
                of: Self.testCalendar.date(byAdding: .day, value: 1, to: Self.july20Date)!
            )!,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health"
        )
        let newerInterval = NormalizedSleepInterval(
            id: "newest-before-refresh",
            startDate: Self.testCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: Self.july24Date)!,
            endDate: Self.testCalendar.date(bySettingHour: 7, minute: 0, second: 0, of: Self.july25Noon)!,
            stage: .core,
            sourceName: "Watch",
            sourceIdentifier: "com.apple.health"
        )
        let model = makeTestModel(
            now: { Self.july25Noon },
            intervals: [olderInterval, newerInterval]
        )
        await model.loadData()
        model.selectNight(Self.july20Date)
        model.updateViewport(
            start: model.viewportStart.addingTimeInterval(30 * 60),
            end: model.viewportEnd.addingTimeInterval(-30 * 60)
        )
        model.selectedInterval = olderInterval
        let expectedViewportStart = model.viewportStart
        let expectedViewportEnd = model.viewportEnd

        await model.handleScenePhaseChange(.active)

        #expect(Self.testCalendar.isDate(model.selectedDate, inSameDayAs: Self.july20Date))
        #expect(model.viewportStart == expectedViewportStart)
        #expect(model.viewportEnd == expectedViewportEnd)
        #expect(model.selectedInterval == olderInterval)
    }

    @Test @MainActor func sceneActivationKeepsLoadedContentVisibleDuringRefresh() async {
        let store = BlockingSleepStore(intervals: [])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = NightBrowserModel(
            store: store,
            preferencesStore: PreferencesStore(userDefaults: defaults),
            now: { Self.july25Noon }
        )
        await model.loadData()
        await store.blockNextFetch()

        let refresh = Task {
            await model.handleScenePhaseChange(.active)
        }
        await store.waitForFetchCount(2)

        #expect(model.appState == .loaded)

        await store.resumeFetch()
        await refresh.value
    }

    @Test @MainActor func overlappingSceneActivationsShareOneRefresh() async {
        let store = BlockingSleepStore(intervals: [])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = NightBrowserModel(
            store: store,
            preferencesStore: PreferencesStore(userDefaults: defaults),
            now: { Self.july25Noon }
        )
        await model.loadData()
        await store.blockNextFetch()

        let firstRefresh = Task {
            await model.handleScenePhaseChange(.active)
        }
        await store.waitForFetchCount(2)
        let overlappingRefresh = Task {
            await model.handleScenePhaseChange(.active)
        }
        await overlappingRefresh.value
        let fetchCount = await store.currentFetchCount()

        #expect(fetchCount == 2)

        await store.resumeFetch()
        await firstRefresh.value
    }

    @Test @MainActor func inactiveAndBackgroundScenePhasesDoNotRefresh() async {
        let store = BlockingSleepStore(intervals: [])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = NightBrowserModel(
            store: store,
            preferencesStore: PreferencesStore(userDefaults: defaults),
            now: { Self.july25Noon }
        )
        await model.loadData()

        await model.handleScenePhaseChange(.inactive)
        await model.handleScenePhaseChange(.background)
        let fetchCount = await store.currentFetchCount()

        #expect(fetchCount == 1)
    }

    @Test @MainActor func viewportFocusesDetectedSleepWithGutter() async {
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

        // The detected span (23:00 – 06:00) is padded by the gutter rather than expanded
        // to the full configured window (19:00 – 07:00), so empty configured time is hidden.
        let expectedStart = sleepStart.addingTimeInterval(-AssembledNight.detectedViewportGutter)
        let expectedEnd = sleepEnd.addingTimeInterval(AssembledNight.detectedViewportGutter)
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

    @Test @MainActor func testTogglingBriefAwakeFilterKeepsTheViewport() async {
        let fixtureStore = FixtureSleepStore()
        let testDefaults = UserDefaults(suiteName: "NightBrowserModelTestsBriefAwake")!
        testDefaults.removePersistentDomain(forName: "NightBrowserModelTestsBriefAwake")
        let prefsStore = PreferencesStore(userDefaults: testDefaults)

        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore)
        await model.loadData()

        // Zoom in an hour on each side, then remember where we ended up.
        model.updateViewport(
            start: model.viewportStart.addingTimeInterval(3600),
            end: model.viewportEnd.addingTimeInterval(-3600)
        )
        let expectedStart = model.viewportStart
        let expectedEnd = model.viewportEnd
        model.selectedInterval = model.selectedAssembledNight?.primaryLaneIntervals.first

        model.toggleHideBriefAwakes()

        #expect(model.preferences.hidesBriefAwakes == true)
        #expect(model.viewportStart == expectedStart)
        #expect(model.viewportEnd == expectedEnd)
        // A selection made before the toggle may name an interval the display lane no longer has.
        #expect(model.selectedInterval == nil)

        model.toggleHideBriefAwakes()

        #expect(model.preferences.hidesBriefAwakes == false)
        #expect(model.viewportStart == expectedStart)
        #expect(model.viewportEnd == expectedEnd)
    }

    @Test @MainActor func testTogglingBriefAwakeFilterPersists() async {
        let fixtureStore = FixtureSleepStore()
        let testDefaults = UserDefaults(suiteName: "NightBrowserModelTestsBriefAwakePersist")!
        testDefaults.removePersistentDomain(forName: "NightBrowserModelTestsBriefAwakePersist")
        let prefsStore = PreferencesStore(userDefaults: testDefaults)

        let model = NightBrowserModel(store: fixtureStore, preferencesStore: prefsStore)
        await model.loadData()
        model.toggleHideBriefAwakes()

        #expect(prefsStore.load().hidesBriefAwakes == true)
    }
}

private actor BlockingSleepStore: HealthKitSleepStoreProtocol {
    private let intervals: [NormalizedSleepInterval]
    private var fetchCount = 0
    private var blocksNextFetch = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?

    init(intervals: [NormalizedSleepInterval]) {
        self.intervals = intervals
    }

    func requestAuthorization() async throws -> Bool {
        true
    }

    func fetchSleepSamples(start: Date, end: Date) async throws -> [NormalizedSleepInterval] {
        fetchCount += 1
        if blocksNextFetch {
            blocksNextFetch = false
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
            }
        }
        return intervals.filter { $0.endDate > start && $0.startDate < end }
    }

    func blockNextFetch() {
        blocksNextFetch = true
    }

    func waitForFetchCount(_ expectedCount: Int) async {
        while fetchCount < expectedCount {
            await Task.yield()
        }
    }

    func currentFetchCount() -> Int {
        fetchCount
    }

    func resumeFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }
}
