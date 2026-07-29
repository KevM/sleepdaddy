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
        #expect(prefs.hidesBriefAwakes == false)
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

    @Test func testDecodingPreferencesSavedBeforeBriefAwakeFlagKeepsEverythingElse() throws {
        // Written by a build that predates `hidesBriefAwakes`. Decoding must not throw:
        // PreferencesStore turns a decode failure into `.default`, silently wiping the
        // user's window, sources, and exclusions.
        let legacyJSON = Data("""
        {
            "coreWindowStartHour": 20,
            "coreWindowEndHour": 6,
            "selectedSourceIdentifiers": ["com.apple.health"],
            "excludedSampleIDs": ["sample-1"]
        }
        """.utf8)

        let prefs = try JSONDecoder().decode(SleepPreferences.self, from: legacyJSON)

        #expect(prefs.coreWindowStartHour == 20)
        #expect(prefs.coreWindowEndHour == 6)
        #expect(prefs.selectedSourceIdentifiers == ["com.apple.health"])
        #expect(prefs.excludedSampleIDs == ["sample-1"])
        #expect(prefs.hidesBriefAwakes == false)
    }

    @Test func testBriefAwakeFlagRoundTripsThroughTheStore() {
        let testDefaults = UserDefaults(suiteName: "SleepPreferencesTestsBriefAwake")!
        testDefaults.removePersistentDomain(forName: "SleepPreferencesTestsBriefAwake")

        let store = PreferencesStore(userDefaults: testDefaults)
        var prefs = store.load()
        prefs.hidesBriefAwakes = true
        store.save(prefs)

        #expect(store.load().hidesBriefAwakes == true)
    }
}
