import SwiftUI
import HealthKit

@main
struct SleepDaddyApp: App {
    @State private var model: NightBrowserModel

    init() {
        #if targetEnvironment(simulator)
        let store = FixtureSleepStore()
        #else
        let store: HealthKitSleepStoreProtocol = HKHealthStore.isHealthDataAvailable() ? HealthKitSleepStore() : FixtureSleepStore()
        #endif
        _model = State(initialValue: NightBrowserModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
