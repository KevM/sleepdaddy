import Foundation

public final class FixtureSleepStore: HealthKitSleepStoreProtocol, @unchecked Sendable {
    public var customIntervals: [NormalizedSleepInterval]?
    private let isAuthorized: Bool

    public init(customIntervals: [NormalizedSleepInterval]? = nil, isAuthorized: Bool = true) {
        self.customIntervals = customIntervals
        self.isAuthorized = isAuthorized
    }

    public func requestAuthorization() async throws -> Bool {
        return isAuthorized
    }

    public func fetchSleepSamples(start: Date, end: Date) async throws -> [NormalizedSleepInterval] {
        if let custom = customIntervals {
            return custom.filter { $0.endDate > start && $0.startDate < end }
        }
        return FixtureSleepStore.generateDefaultFixtures(from: start, to: end)
    }

    public static func generateDefaultFixtures(from startDate: Date, to endDate: Date) -> [NormalizedSleepInterval] {
        var intervals: [NormalizedSleepInterval] = []
        let calendar = Calendar.current

        // Generate fixture nights for days overlapping the range
        var currentDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        while currentDay <= endDay {
            let nightIntervals = createFixtureNight(forDay: currentDay)
            intervals.append(contentsOf: nightIntervals)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }

        return intervals
    }

    public static func createFixtureNight(forDay day: Date) -> [NormalizedSleepInterval] {
        let calendar = Calendar.current
        // Core night starts at 7:00 PM on day, ends at 7:00 AM on next day
        guard let base7PM = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
              let base7AM = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: nextDay) else {
            return []
        }

        let dayString = ISO8601DateFormatter().string(from: day)

        // Apple Watch Source
        let watchSource = "Apple Watch"
        let watchID = "com.apple.health"

        // In Bed: 10:30 PM to 6:45 AM
        let inBedStart = base7PM.addingTimeInterval(3.5 * 3600) // 10:30 PM
        let inBedEnd = base7AM.addingTimeInterval(-0.25 * 3600) // 6:45 AM

        var result: [NormalizedSleepInterval] = []

        result.append(NormalizedSleepInterval(
            id: "fixture-inbed-\(dayString)",
            startDate: inBedStart,
            endDate: inBedEnd,
            stage: .inBed,
            sourceName: watchSource,
            sourceIdentifier: watchID,
            deviceModel: "Watch7,1",
            bundleIdentifier: watchID
        ))

        // Detailed stages within inBed (11:00 PM to 6:30 AM)
        let sleepStart = base7PM.addingTimeInterval(4.0 * 3600) // 11:00 PM
        var currentTime = sleepStart

        let stages: [(SleepStage, TimeInterval)] = [
            (.core, 45 * 60),      // 11:00 PM - 11:45 PM
            (.deep, 60 * 60),      // 11:45 PM - 12:45 AM
            (.rem, 45 * 60),       // 12:45 AM - 01:30 AM
            (.core, 90 * 60),      // 01:30 AM - 03:00 AM
            (.awake, 15 * 60),     // 03:00 AM - 03:15 AM
            (.deep, 45 * 60),      // 03:15 AM - 04:00 AM
            (.rem, 60 * 60),       // 04:00 AM - 05:00 AM
            (.core, 60 * 60),      // 05:00 AM - 06:00 AM
            (.rem, 30 * 60)        // 06:00 AM - 06:30 AM
        ]

        for (idx, (stage, duration)) in stages.enumerated() {
            let itemEnd = currentTime.addingTimeInterval(duration)
            result.append(NormalizedSleepInterval(
                id: "fixture-\(stage.rawValue)-\(idx)-\(dayString)",
                startDate: currentTime,
                endDate: itemEnd,
                stage: stage,
                sourceName: watchSource,
                sourceIdentifier: watchID,
                deviceModel: "Watch7,1",
                bundleIdentifier: watchID
            ))
            currentTime = itemEnd
        }

        // Second Source: Oura Ring with slight overlap conflict
        let ouraSource = "Oura Ring"
        let ouraID = "com.ouraring.oura"

        // Oura sees deep sleep starting slightly earlier (11:30 PM - 1:00 AM)
        result.append(NormalizedSleepInterval(
            id: "fixture-oura-deep-\(dayString)",
            startDate: sleepStart.addingTimeInterval(30 * 60),
            endDate: sleepStart.addingTimeInterval(120 * 60),
            stage: .deep,
            sourceName: ouraSource,
            sourceIdentifier: ouraID,
            deviceModel: "Ring Gen3",
            bundleIdentifier: ouraID
        ))

        return result
    }
}
