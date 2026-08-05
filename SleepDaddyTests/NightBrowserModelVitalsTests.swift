import Testing
import Foundation
import UniformTypeIdentifiers
@testable import SleepDaddy

/// An in-memory store so the model can be exercised without touching the file system.
final class InMemoryVitalsStore: VitalsStore, @unchecked Sendable {
    var sessions: [VitalsSession] = []
    var loadDelayNanoseconds: UInt64 = 0

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
        loadSessionCallCount += 1
        if loadDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(loadDelayNanoseconds) / 1_000_000_000.0)
        }
        return sessions.first { $0.startDate == descriptor.start }!
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
