import Testing
import Foundation
import UniformTypeIdentifiers
@testable import SleepDaddy

/// An in-memory store so the model can be exercised without touching the file system.
final class InMemoryVitalsStore: VitalsStore, @unchecked Sendable {
    var sessions: [VitalsSession] = []
    var loadDelayNanoseconds: UInt64 = 0
    var loadDelaysByCall: [UInt64] = []

    func importRecording(_ data: Data, originalName: String) throws -> VitalsRecordingDescriptor {
        let session = try CheckmeCSVParser().parse(data, fileName: originalName)
        sessions.append(session)
        return VitalsRecordingDescriptor(
            start: session.startDate, end: session.endDate,
            url: URL(fileURLWithPath: "/dev/null")
        )
    }

    func allDescriptors() throws -> [VitalsRecordingDescriptor] {
        sessions.map {
            VitalsRecordingDescriptor(
                start: $0.startDate, end: $0.endDate,
                url: URL(fileURLWithPath: "/\($0.id)")
            )
        }
    }

    func descriptors(overlapping interval: DateInterval) throws -> [VitalsRecordingDescriptor] {
        try allDescriptors().filter { $0.dateInterval.intersects(interval) }
    }

    /// Counts entries, so a test can wait for a load to have genuinely reached the store
    /// rather than guessing at a delay long enough for it to have started.
    private(set) var loadSessionCallCount = 0

    func loadSession(for descriptor: VitalsRecordingDescriptor) throws -> VitalsSession {
        let callIndex = loadSessionCallCount
        loadSessionCallCount += 1
        let delay = loadDelaysByCall.indices.contains(callIndex)
            ? loadDelaysByCall[callIndex] : loadDelayNanoseconds
        let result = sessions.first { $0.startDate == descriptor.start }!
        if delay > 0 {
            Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000.0)
        }
        return result
    }

    func originalCSV(for descriptor: VitalsRecordingDescriptor) throws -> Data { Data() }
}

struct NightBrowserModelVitalsTests {
    private func session(start: Date, count: Int) -> VitalsSession {
        VitalsSession(
            id: "s-\(start.timeIntervalSinceReferenceDate)",
            startDate: start,
            spo2: Array(repeating: UInt8(95), count: count),
            pulse: Array(repeating: UInt8(60), count: count),
            motion: Array(repeating: UInt8(0), count: count),
            sourceFileNames: []
        )
    }

    @Test func aNightWithNoVitalsExposesNoSession() async {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        await model.loadData()
        #expect(model.selectedVitalsSession == nil)
        #expect(model.selectedDesaturationEvents.isEmpty)
    }

    @Test func aSessionOverlappingTheSelectedNightIsExposed() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store,
            now: { Date() }
        )
        await model.loadData()

        let night = try #require(model.selectedAssembledNight)
        #expect(night.hasSleepData)
        store.sessions = [session(start: night.detectedStart, count: 1_000)]
        await model.loadVitalsForSelectedNight()

        #expect(model.selectedVitalsSession != nil)
    }

    @Test func theSelectedNightCarriesTheVitalsExtent() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        let night = try #require(model.selectedAssembledNight)
        #expect(night.hasSleepData)
        // Start an hour before the detected sleep so the extent must widen.
        let early = night.detectedStart.addingTimeInterval(-3_600)
        store.sessions = [session(start: early, count: 3_000)]
        await model.loadVitalsForSelectedNight()

        let updated = try #require(model.selectedAssembledNight)
        #expect(updated.vitalsExtent != nil)
        #expect(updated.timelineStart <= early)
    }

    @Test func changingNightsAutomaticallyReloadsVitalsWithoutManualLoaderCall() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        let currentNight = try #require(model.selectedAssembledNight)
        #expect(currentNight.hasSleepData)
        #expect(model.canSelectPreviousNight)

        let prevNightDate = model.assembledNights[model.currentNightIndex! - 1].date
        let prevNightObj = model.assembledNights[model.currentNightIndex! - 1]

        let prevSession = session(start: prevNightObj.detectedStart, count: 1_000)
        store.sessions = [prevSession]

        // Switch night via API call (which sets selectedDate)
        model.selectPreviousNight()
        #expect(Calendar.current.isDate(model.selectedDate, inSameDayAs: prevNightDate))

        // Wait for async task dispatched in didSet to complete
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(model.selectedVitalsSession != nil)
        #expect(model.selectedVitalsSession?.startDate == prevSession.startDate)
    }

    @Test func reassembleNightsPreservesVitalsExtentOnSelectedNight() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        let night = try #require(model.selectedAssembledNight)
        let early = night.detectedStart.addingTimeInterval(-3_600)
        store.sessions = [session(start: early, count: 3_000)]
        await model.loadVitalsForSelectedNight()

        #expect(model.selectedAssembledNight?.vitalsExtent != nil)

        // Trigger reassembly (e.g. settings toggle or source toggle)
        model.reassembleNights(preservingViewport: true)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(model.selectedAssembledNight?.vitalsExtent != nil)
    }

    @Test func rapidDateChangesDiscardStaleVitalsFromEarlierNight() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        // Night A's recording has to be in the store *before* its load begins, and that
        // load has to still be in flight when the test navigates away. Populating the
        // store after `loadData` instead would leave nothing stale to discard, and the
        // test would pass whether or not the model guards the write-back.
        let nightA = try #require(model.selectedAssembledNight)
        store.sessions = [session(start: nightA.detectedStart, count: 1_000)]
        store.loadDelayNanoseconds = 200_000_000

        async let nightALoad: Void = model.loadVitalsForSelectedNight()

        // Wait on the store being reached rather than on a delay chosen to outrun it.
        try await waitUntil { store.loadSessionCallCount > 0 }

        // Night B is a day away from night A's recording, so it resolves to nothing.
        model.selectPreviousNight()
        await nightALoad

        // Night A's load returns after the selection moved. Watch across a window wide
        // enough that a stale write would have landed inside it, and report once rather
        // than recording the same failure on every poll.
        var leaked = false
        for _ in 0..<20 where !leaked {
            try await Task.sleep(nanoseconds: 10_000_000)
            leaked = model.selectedVitalsSession != nil
                || !model.selectedDesaturationEvents.isEmpty
                || model.selectedAssembledNight?.vitalsExtent != nil
        }
        #expect(!leaked, "night A's recording landed on night B after the selection moved")
    }

    @Test func supersededSameNightLoadCannotClearANewerResult() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()
        let night = try #require(model.selectedAssembledNight)
        store.sessions = [session(start: night.detectedStart, count: 1_000)]
        store.loadDelaysByCall = [200_000_000, 0]

        async let older: Void = model.loadVitalsForSelectedNight()
        try await waitUntil { store.loadSessionCallCount == 1 }
        await model.loadVitalsForSelectedNight()
        #expect(model.selectedVitalsSession != nil)
        await older

        #expect(model.selectedVitalsSession != nil)
        #expect(model.selectedAssembledNight?.vitalsExtent != nil)
    }

    @Test func importVitalsAutoSelectsTheNightOfTheRecording() async throws {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        let prevNight = model.assembledNights[model.currentNightIndex! - 1]

        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss MMM dd yyyy"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = Calendar.current.timeZone
        let stamp1 = df.string(from: prevNight.detectedStart)
        let stamp2 = df.string(from: prevNight.detectedStart.addingTimeInterval(2))
        let text = "Time,Oxygen Level,Pulse Rate,Motion\n\(stamp1),96,70,0\n\(stamp2),95,69,0"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import.csv")
        try Data(text.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await model.importVitals(from: tempURL)

        #expect(Calendar.current.isDate(model.selectedDate, inSameDayAs: prevNight.date))
        #expect(model.selectedVitalsSession != nil)
    }

    @Test func importOlderThanOverviewLoadsAndSelectsItsNight() async throws {
        let store = InMemoryVitalsStore()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { now }
        )
        await model.loadData()

        let text = """
        Time,Oxygen Level,Pulse Rate,Motion
        22:00:00 Jan 03 2026,96,70,0
        22:00:02 Jan 03 2026,95,69,0
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("old-import-\(UUID().uuidString).csv")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await model.importVitals(from: url)

        #expect(Calendar.current.isDate(model.selectedDate, inSameDayAs: store.sessions[0].startDate))
        #expect(model.selectedAssembledNight != nil)
        #expect(model.selectedVitalsSession != nil)
    }

    @Test func importWaitsForAnActiveInitialLoadThenSelectsTheImportedNight() async throws {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let oldNight = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let sleepStore = BlockingSleepStore(
            intervals: FixtureSleepStore.createFixtureNight(forDay: oldNight)
        )
        let vitalsStore = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: sleepStore, vitalsStore: vitalsStore, now: { now }
        )

        await sleepStore.blockNextFetch()
        let initialLoad = Task { await model.loadData() }
        #expect(await sleepStore.waitForFetchCount(1))

        let text = """
        Time,Oxygen Level,Pulse Rate,Motion
        23:30:00 Jan 03 2026,96,70,0
        23:30:02 Jan 03 2026,95,69,0
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("concurrent-import-\(UUID().uuidString).csv")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let importTask = Task { try await model.importVitals(from: url) }
        try await waitUntil { !vitalsStore.sessions.isEmpty }
        await sleepStore.resumeFetch()
        await initialLoad.value
        try await importTask.value

        #expect(calendar.isDate(model.selectedDate, inSameDayAs: oldNight))
        #expect(model.selectedAssembledNight?.hasSleepData == true)
        #expect(model.selectedVitalsSession != nil)
    }

    @Test func afterMidnightImportSelectsTheNightWhoseSleepItOverlaps() async throws {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let vitalsStore = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: vitalsStore, now: { now }
        )
        await model.loadData()

        let priorNight = try #require(model.selectedAssembledNight)
        let twoAM = calendar.date(
            bySettingHour: 2, minute: 0, second: 0,
            of: calendar.date(byAdding: .day, value: 1, to: priorNight.date)!
        )!
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss MMM dd yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        let text = """
        Time,Oxygen Level,Pulse Rate,Motion
        \(formatter.string(from: twoAM)),96,70,0
        \(formatter.string(from: twoAM.addingTimeInterval(2))),95,69,0
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("after-midnight-import-\(UUID().uuidString).csv")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await model.importVitals(from: url)

        #expect(calendar.isDate(model.selectedDate, inSameDayAs: priorNight.date))
        #expect(model.selectedVitalsSession != nil)
    }

    @Test func allowedContentTypesIncludesTextAndDataFallbackTypes() {
        let types = VitalsImportButton.allowedContentTypes
        #expect(types.contains(.commaSeparatedText))
        #expect(types.contains(.plainText))
        #expect(types.contains(.text))
        #expect(types.contains(.data))
    }

    /// Polls `condition` until it holds, bounded by wall clock.
    ///
    /// A fixed sleep would encode a guess about how long the work takes; on a loaded
    /// machine that guess is what makes a test flaky.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @Sendable () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("timed out waiting for condition")
    }
}
