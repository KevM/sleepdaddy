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
            selectedVitalsSession = nil
            selectedDesaturationEvents = []
            resetViewportToSelectedNight()
            Task { @MainActor in
                await loadVitalsForSelectedNight()
            }
        }
    }

    public var viewportStart: Date = Date()
    public var viewportEnd: Date = Date().addingTimeInterval(12 * 3600)

    public var selectedInterval: NormalizedSleepInterval? = nil
    public var showSettings: Bool = false
    public var showShareSheet: Bool = false
    public var exportedImage: UIImage? = nil

    public private(set) var selectedVitalsSession: VitalsSession?
    public private(set) var selectedDesaturationEvents: [DesaturationEvent] = []

    private let store: HealthKitSleepStoreProtocol
    private let preferencesStore: PreferencesStore
    private let vitalsStore: (any VitalsStore)?
    private let detector = DesaturationDetector()
    private let assembler = NightAssembler()
    private let now: @Sendable () -> Date
    private var allFetchedIntervals: [NormalizedSleepInterval] = []
    private var isLoading = false
    private var vitalsTask: Task<(VitalsSession, [DesaturationEvent])?, Never>?

    public init(
        store: HealthKitSleepStoreProtocol = HealthKitSleepStore(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        vitalsStore: (any VitalsStore)? = try? FileVitalsStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.vitalsStore = vitalsStore
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
            await loadVitalsForSelectedNight()
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
        attachVitalsExtent(selectedVitalsSession?.dateInterval)
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

    /// Resolves vitals for the selected night and attaches the extent to it.
    ///
    /// Runs off the main actor: a full recording is roughly 22,000 samples to decompress
    /// and parse. It never touches rendering, which reads the in-memory arrays.
    @MainActor
    public func loadVitalsForSelectedNight() async {
        let targetDate = selectedDate
        vitalsTask?.cancel()

        guard let vitalsStore, let night = selectedAssembledNight else {
            selectedVitalsSession = nil
            selectedDesaturationEvents = []
            return
        }

        // Search a generous window so a recording starting before the detected sleep is
        // still found. The extent, not this window, decides what is drawn.
        let searchWindow = DateInterval(
            start: night.detectedStart.addingTimeInterval(-6 * 3_600),
            end: night.detectedEnd.addingTimeInterval(6 * 3_600)
        )

        let detector = self.detector
        let workTask: Task<(VitalsSession, [DesaturationEvent])?, Never> = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let session = try? vitalsStore.session(covering: searchWindow)
            else { return nil }
            // Decompressing and parsing is the expensive half. If a newer request has
            // superseded this one by the time that finishes, skip detection rather than
            // scanning 22,000 samples for a night nobody is looking at.
            guard !Task.isCancelled else { return nil }
            return (session, detector.events(in: session))
        }

        // The work task itself is what gets cancelled — a wrapper awaiting its value
        // would not, since a detached task has no parent to propagate cancellation from.
        vitalsTask = workTask

        let loaded = await workTask.value

        // Cancellation cannot interrupt the store's synchronous read, so a superseded
        // load still arrives here. The selection is what decides whether it may land.
        guard !Task.isCancelled, selectedDate == targetDate else { return }

        guard let (session, events) = loaded else {
            selectedVitalsSession = nil
            selectedDesaturationEvents = []
            attachVitalsExtent(nil)
            return
        }

        selectedVitalsSession = session
        selectedDesaturationEvents = events
        attachVitalsExtent(session.dateInterval)
    }

    private func attachVitalsExtent(_ extent: DateInterval?) {
        guard let index = currentNightIndex else { return }
        assembledNights[index] = assembledNights[index].withVitalsExtent(extent)
    }

    /// Imports a CSV and refreshes the current night if the recording lands on it.
    @MainActor
    public func importVitals(from url: URL) async throws {
        guard let vitalsStore else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        try vitalsStore.importRecording(data, originalName: url.lastPathComponent)
        await loadVitalsForSelectedNight()
    }
}
