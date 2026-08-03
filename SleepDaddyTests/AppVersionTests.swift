import Testing
import Foundation
@testable import SleepDaddy

struct AppVersionTests {
    /// A real bundle, so the keys and the reads are the ones the app performs. The regression
    /// this guards: Settings printed a literal "1.0" long after project.yml had moved on.
    private let bundle = Bundle(for: InfoDictionaryStub.self)

    @Test func testVersionComesFromTheBundle() throws {
        let shortVersion = try #require(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        #expect(AppVersion.version(bundle: bundle) == shortVersion)
        #expect(AppVersion.version(bundle: bundle) != "Unknown")
    }

    @Test func testBuildComesFromTheBundle() throws {
        let build = try #require(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        #expect(AppVersion.build(bundle: bundle) == build)
    }

    @Test func testMissingVersionReadsAsUnknownRatherThanBlank() {
        #expect(AppVersion.normalizedVersion(nil) == "Unknown")
        #expect(AppVersion.normalizedVersion("   ") == "Unknown")
        #expect(AppVersion.normalizedVersion("1.0.14") == "1.0.14")
    }

    @Test func testMissingBuildIsNilSoSettingsCanDropTheRow() {
        #expect(AppVersion.normalizedBuild(nil) == nil)
        #expect(AppVersion.normalizedBuild("   ") == nil)
        #expect(AppVersion.normalizedBuild("14") == "14")
    }
}

/// Only exists to hand `Bundle(for:)` a class in the test bundle.
private final class InfoDictionaryStub {}
