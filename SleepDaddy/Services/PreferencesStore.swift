import Foundation

public final class PreferencesStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "fm.rodeo.sleepdaddy.preferences"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> SleepPreferences {
        guard let data = userDefaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(SleepPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }

    public func save(_ preferences: SleepPreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            userDefaults.set(data, forKey: key)
        }
    }
}
