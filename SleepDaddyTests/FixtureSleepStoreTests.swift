import Testing
@testable import SleepDaddy

struct FixtureSleepStoreTests {
    @Test func requestAuthorizationUsesConfiguredResult() async throws {
        let deniedStore = FixtureSleepStore(isAuthorized: false)
        let authorizedStore = FixtureSleepStore(isAuthorized: true)

        let deniedResult = try await deniedStore.requestAuthorization()
        let authorizedResult = try await authorizedStore.requestAuthorization()

        #expect(deniedResult == false)
        #expect(authorizedResult == true)
    }
}
