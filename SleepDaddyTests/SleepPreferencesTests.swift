import Testing
import Foundation
@testable import SleepDaddy

struct SleepPreferencesTests {
    @Test func testPreferencesDefaults() {
        let prefs = SleepPreferences.default
        #expect(prefs.coreWindowStartHour == 19)
        #expect(prefs.coreWindowEndHour == 7)
        #expect(prefs.selectedSourceIdentifiers.isEmpty)
        #expect(prefs.excludedSampleIDs.isEmpty)
    }

    @Test func testPreferencesPersistence() {
        let testDefaults = UserDefaults(suiteName: "SleepPreferencesTests")!
        testDefaults.removePersistentDomain(forName: "SleepPreferencesTests")

        let store = PreferencesStore(userDefaults: testDefaults)
        var prefs = store.load()

        prefs.coreWindowStartHour = 20
        prefs.selectedSourceIdentifiers = ["com.apple.health"]
        prefs.excludedSampleIDs = ["sample-1"]

        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.coreWindowStartHour == 20)
        #expect(reloaded.selectedSourceIdentifiers.contains("com.apple.health"))
        #expect(reloaded.excludedSampleIDs.contains("sample-1"))
    }
}
