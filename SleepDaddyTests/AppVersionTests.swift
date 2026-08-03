import Testing
import Foundation
@testable import SleepDaddy

struct AppVersionTests {
    @Test func testVersionComesFromTheBundle() throws {
        // A real bundle, so the key and the read are the ones the app performs. The regression
        // this guards: Settings printed a literal "1.0" long after project.yml had moved on.
        let bundle = Bundle(for: InfoDictionaryStub.self)
        let shortVersion = try #require(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        #expect(AppVersion.version(bundle: bundle) == shortVersion)
        #expect(AppVersion.version(bundle: bundle) != "Unknown")
    }

    @Test func testMissingVersionReadsAsUnknownRatherThanBlank() {
        #expect(AppVersion.normalizedVersion(nil) == "Unknown")
        #expect(AppVersion.normalizedVersion("   ") == "Unknown")
        #expect(AppVersion.normalizedVersion("1.0.14") == "1.0.14")
    }
}

/// Only exists to hand `Bundle(for:)` a class in the test bundle.
private final class InfoDictionaryStub {}
