import Testing
import Foundation
@testable import SleepDaddy

/// An in-memory store so the model can be exercised without touching the file system.
final class InMemoryVitalsStore: VitalsStore, @unchecked Sendable {
    var sessions: [VitalsSession] = []

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

    func loadSession(for descriptor: VitalsRecordingDescriptor) throws -> VitalsSession {
        sessions.first { $0.startDate == descriptor.start }!
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

    @Test func aSessionOverlappingTheSelectedNightIsExposed() async {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store,
            now: { Date() }
        )
        await model.loadData()

        guard let night = model.selectedAssembledNight, night.hasSleepData else { return }
        store.sessions = [session(start: night.detectedStart, count: 1_000)]
        await model.loadVitalsForSelectedNight()

        #expect(model.selectedVitalsSession != nil)
    }

    @Test func theSelectedNightCarriesTheVitalsExtent() async {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        guard let night = model.selectedAssembledNight, night.hasSleepData else { return }
        // Start an hour before the detected sleep so the extent must widen.
        let early = night.detectedStart.addingTimeInterval(-3_600)
        store.sessions = [session(start: early, count: 3_000)]
        await model.loadVitalsForSelectedNight()

        let updated = try! #require(model.selectedAssembledNight)
        #expect(updated.vitalsExtent != nil)
        #expect(updated.timelineStart <= early)
    }
}
