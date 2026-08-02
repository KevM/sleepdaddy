import SwiftUI
import Observation
import HealthKit

public enum AppState: Equatable, Sendable {
    case loading
    case unavailable
    case unauthorized
    case loaded
    case error(String)
}

@Observable
public final class NightBrowserModel: @unchecked Sendable {
    public private(set) var appState: AppState = .loading
    public private(set) var preferences: SleepPreferences = .default
    public private(set) var availableSources: [String: String] = [:] // [Identifier: Name]
    public private(set) var assembledNights: [AssembledNight] = []

    public var selectedDate: Date = Calendar.current.startOfDay(for: Date()) {
        didSet {
            selectedInterval = nil
            resetViewportToSelectedNight()
        }
    }

    public var viewportStart: Date = Date()
    public var viewportEnd: Date = Date().addingTimeInterval(12 * 3600)

    public var selectedInterval: NormalizedSleepInterval? = nil
    public var showSettings: Bool = false
    public var showShareSheet: Bool = false
    public var exportedImage: UIImage? = nil

    private let store: HealthKitSleepStoreProtocol
    private let preferencesStore: PreferencesStore
    private let assembler = NightAssembler()
    private let now: @Sendable () -> Date
    private var allFetchedIntervals: [NormalizedSleepInterval] = []
    private var isLoading = false

    public init(
        store: HealthKitSleepStoreProtocol = HealthKitSleepStore(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.now = now
        self.preferences = preferencesStore.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        self.selectedDate = today
        self.viewportStart = today
        self.viewportEnd = today.addingTimeInterval(12 * 3600)
    }

    @MainActor
    public func loadData(preservingNavigationState: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if appState != .loaded {
            appState = .loading
        }

        guard HKHealthStore.isHealthDataAvailable() || !(store is HealthKitSleepStore) else {
            appState = .unavailable
            return
        }

        do {
            let authResult = try await store.requestAuthorization()
            if !authResult {
                appState = .unauthorized
                return
            }

            // Fetch 21 days of buffered data (14 days before today + 7 days buffer)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now())
            let start = calendar.date(byAdding: .day, value: -14, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 2, to: today) ?? today

            let raw = try await store.fetchSleepSamples(start: start, end: end)
            self.allFetchedIntervals = raw

            // Extract unique sources
            var sources: [String: String] = [:]
            for interval in raw {
                sources[interval.sourceIdentifier] = interval.sourceName
            }
            self.availableSources = sources

            reassembleNights(preservingViewport: preservingNavigationState)

            let selectionStillExists = assembledNights.contains {
                calendar.isDate($0.date, inSameDayAs: selectedDate)
            }

            // Initial loads open to the most recent night. Foreground refreshes preserve
            // the user's current date, viewport, and inspected interval while it remains
            // inside the rebuilt overview window.
            if preservingNavigationState && selectionStillExists {
                // Keep the current navigation state.
            } else if let newest = assembledNights.last(where: { $0.hasSleepData }) {
                if !calendar.isDate(selectedDate, inSameDayAs: newest.date) {
                    self.selectedDate = newest.date
                }
            } else {
                let fallback = calendar.date(byAdding: .day, value: -1, to: today) ?? today
                if !calendar.isDate(selectedDate, inSameDayAs: fallback) {
                    self.selectedDate = fallback
                }
            }

            appState = .loaded
        } catch where preservingNavigationState {
            // Keep the last successfully loaded timeline visible when a foreground
            // refresh encounters a transient HealthKit failure.
        } catch {
            appState = .error(error.localizedDescription)
        }
    }

    @MainActor
    public func handleScenePhaseChange(_ scenePhase: ScenePhase) async {
        guard scenePhase == .active else { return }
        await loadData(preservingNavigationState: appState == .loaded)
    }

    public var selectedAssembledNight: AssembledNight? {
        assembledNights.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    /// - Parameter preservingViewport: pass `true` for display-only preferences that cannot
    ///   move a night's bounds, or for a foreground refresh where preserving the user's
    ///   navigation takes precedence even if newly fetched intervals move those bounds.
    ///   Source selection and core-window changes must still re-derive the viewport.
    public func reassembleNights(preservingViewport: Bool = false) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())

        // Assemble 14 nearby nights (-13 to 0)
        var newNights: [AssembledNight] = []
        for offset in (-13)...0 {
            if let date = calendar.date(byAdding: .day, value: offset, to: today) {
                let night = assembler.assembleNight(
                    for: date,
                    allNormalizedIntervals: allFetchedIntervals,
                    preferences: preferences
                )
                newNights.append(night)
            }
        }
        self.assembledNights = newNights.sorted { $0.date < $1.date }

        if !preservingViewport {
            resetViewportToSelectedNight()
        }
    }

    public func resetViewportToSelectedNight() {
        if let current = selectedAssembledNight {
            self.viewportStart = current.preferredViewportStart
            self.viewportEnd = current.preferredViewportEnd
        } else {
            let calendar = Calendar.current
            let start = calendar.date(bySettingHour: preferences.coreWindowStartHour, minute: 0, second: 0, of: selectedDate) ?? selectedDate
            let end = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            self.viewportStart = start
            self.viewportEnd = end
        }
    }

    public func toggleSourceSelection(_ sourceIdentifier: String) {
        var updated = preferences.selectedSourceIdentifiers
        if let idx = updated.firstIndex(of: sourceIdentifier) {
            updated.remove(at: idx)
        } else {
            updated.append(sourceIdentifier)
        }
        preferences.selectedSourceIdentifiers = updated
        preferencesStore.save(preferences)
        reassembleNights()
    }

    public func clearSourceSelection() {
        preferences.selectedSourceIdentifiers = []
        preferencesStore.save(preferences)
        reassembleNights()
    }

    public func toggleHideBriefAwakes() {
        preferences.hidesBriefAwakes.toggle()
        preferencesStore.save(preferences)
        // The selection may name an interval that is no longer in the display lane, which
        // would leave the inspector open over a segment the canvas can no longer emphasise.
        selectedInterval = nil
        reassembleNights(preservingViewport: true)
    }

    public func updateCoreWindow(startHour: Int, endHour: Int) {
        preferences.coreWindowStartHour = startHour
        preferences.coreWindowEndHour = endHour
        preferencesStore.save(preferences)
        reassembleNights()
    }

    public func selectNight(_ date: Date) {
        self.selectedDate = date
    }

    public func updateViewport(start: Date, end: Date) {
        guard let current = selectedAssembledNight else { return }
        // The viewport is still stored as two loose Dates, so both the current and the
        // proposed window are normalized here. Task 6 closes this gap by storing a
        // `TimelineViewport` directly.
        let geom = SleepTimelineGeometry(
            totalStart: current.timelineStart,
            totalEnd: current.timelineEnd,
            viewport: TimelineViewport(normalizing: viewportStart, end: viewportEnd),
            canvasWidth: 300,
            canvasHeight: 300
        )
        let clamped = geom.clamped(TimelineViewport(normalizing: start, end: end))
        self.viewportStart = clamped.start
        self.viewportEnd = clamped.end
    }

    public var currentNightIndex: Int? {
        assembledNights.firstIndex { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    public var canSelectPreviousNight: Bool {
        guard let idx = currentNightIndex else { return false }
        return idx > 0
    }

    public var canSelectNextNight: Bool {
        guard let idx = currentNightIndex else { return false }
        return idx < assembledNights.count - 1
    }

    public func selectPreviousNight() {
        guard canSelectPreviousNight, let idx = currentNightIndex else { return }
        selectNight(assembledNights[idx - 1].date)
    }

    public func selectNextNight() {
        guard canSelectNextNight, let idx = currentNightIndex else { return }
        selectNight(assembledNights[idx + 1].date)
    }
}
