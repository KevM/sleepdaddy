import SwiftUI

enum SelectedNightLayoutMode: Equatable {
    case standard
    case immersiveLandscape

    static func resolve(verticalSizeClass: UserInterfaceSizeClass?) -> SelectedNightLayoutMode {
        verticalSizeClass == .compact ? .immersiveLandscape : .standard
    }
}

public struct ContentView: View {
    @State private var model: NightBrowserModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(model: NightBrowserModel? = nil) {
        self._model = State(initialValue: model ?? NightBrowserModel())
    }

    private var currentLayoutMode: SelectedNightLayoutMode {
        SelectedNightLayoutMode.resolve(verticalSizeClass: verticalSizeClass)
    }

    private var selectedDateRange: ClosedRange<Date>? {
        guard let first = model.assembledNights.first?.date,
              let last = model.assembledNights.last?.date,
              first <= last else { return nil }
        return first...last
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch model.appState {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Reading HealthKit sleep data...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .unavailable:
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("HealthKit Unavailable")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("HealthKit is not available on this device or environment.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .unauthorized:
                    VStack(spacing: 16) {
                        Image(systemName: "hand.raised.slash.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        Text("HealthKit Access Required")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("SleepDaddy needs read-only access to visualize your HealthKit sleep analysis. Enable sleep data access in iOS Settings > Health > Data Access & Devices > SleepDaddy.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button("Retry Access Check") {
                            Task {
                                await model.loadData()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .error(let errorMsg):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Unable to Load Sleep Data")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(errorMsg)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button("Retry") {
                            Task {
                                await model.loadData()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded:
                    VStack(spacing: 0) {
                        if currentLayoutMode == .standard {
                            if let night = model.selectedAssembledNight {
                                NightHeaderView(
                                    night: night,
                                    canGoPrevious: model.canSelectPreviousNight,
                                    canGoNext: model.canSelectNextNight,
                                    dateRange: selectedDateRange,
                                    onPrevious: model.selectPreviousNight,
                                    onNext: model.selectNextNight,
                                    onSelectDate: model.selectNight
                                )
                            }

                            Divider()
                                .padding(.vertical, 8)

                            // Selected Night Detail
                            SelectedNightDetailView(model: model)
                            .padding(.vertical, 8)
                        } else {
                            SelectedNightDetailView(model: model)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                }
            }
            .navigationTitle("SleepDaddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.appState == .loaded,
                   currentLayoutMode == .immersiveLandscape,
                   let night = model.selectedAssembledNight {
                    ToolbarItem(placement: .principal) {
                        LandscapeNightToolbarView(
                            night: night,
                            dateRange: selectedDateRange,
                            canGoPrevious: model.canSelectPreviousNight,
                            canGoNext: model.canSelectNextNight,
                            onPrevious: model.selectPreviousNight,
                            onNext: model.selectNextNight,
                            onSelectDate: model.selectNight
                        )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        CompactSourceFilterButton(
                            availableSources: model.availableSources,
                            selectedSourceIDs: model.preferences.selectedSourceIdentifiers,
                            hidesBriefAwakes: model.preferences.hidesBriefAwakes,
                            onToggleSource: { sourceID in
                                model.toggleSourceSelection(sourceID)
                            },
                            onClearFilter: {
                                model.clearSourceSelection()
                            },
                            onToggleHideBriefAwakes: {
                                model.toggleHideBriefAwakes()
                            }
                        )
                        .accessibilityHint("Filters sleep data by device or application source")

                        Button {
                            if let night = model.selectedAssembledNight, night.hasSleepData {
                                exportAndShare(night: night)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Share timeline")
                        .accessibilityHint("Exports and shares current sleep view as image")
                        .disabled(model.selectedAssembledNight?.hasSleepData != true)

                        Button {
                            model.showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Opens sleep data settings")
                    }
                }
            }
            .sheet(isPresented: $model.showSettings) {
                SettingsView(
                    coreStartHour: Binding(
                        get: { model.preferences.coreWindowStartHour },
                        set: { start in model.updateCoreWindow(startHour: start, endHour: model.preferences.coreWindowEndHour) }
                    ),
                    coreEndHour: Binding(
                        get: { model.preferences.coreWindowEndHour },
                        set: { end in model.updateCoreWindow(startHour: model.preferences.coreWindowStartHour, endHour: end) }
                    ),
                    onDismiss: { model.showSettings = false }
                )
            }
            .sheet(isPresented: $model.showShareSheet) {
                if let img = model.exportedImage {
                    ActivityViewController(activityItems: [img])
                }
            }
            .task(id: scenePhase) {
                await model.handleScenePhaseChange(scenePhase)
            }
        }
    }

    private func exportAndShare(night: AssembledNight) {
        let renderer = SleepShareRenderer()
        let desc = model.preferences.selectedSourceIdentifiers.isEmpty ? "All Sources" : model.preferences.selectedSourceIdentifiers.compactMap { model.availableSources[$0] }.joined(separator: ", ")
        if let image = renderer.renderShareImage(
            night: night,
            viewportStart: model.viewportStart,
            viewportEnd: model.viewportEnd,
            sourceFilterDescription: desc
        ) {
            model.exportedImage = image
            model.showShareSheet = true
        }
    }
}

#if DEBUG

/// Backs previews with fixture sleep data and an isolated preferences domain, so a preview
/// never reads or writes the simulator's real preferences.
private func previewModel(hidesBriefAwakes: Bool,
                          isHealthKitAuthorized: Bool = true) -> NightBrowserModel {
    let suiteName = "fm.rodeo.sleepdaddy.previews.\(hidesBriefAwakes).\(isHealthKitAuthorized)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let preferencesStore = PreferencesStore(userDefaults: defaults)
    var preferences = SleepPreferences.default
    preferences.hidesBriefAwakes = hidesBriefAwakes
    preferencesStore.save(preferences)

    return NightBrowserModel(
        store: FixtureSleepStore(isAuthorized: isHealthKitAuthorized),
        preferencesStore: preferencesStore
    )
}

#Preview("Filter active") {
    ContentView(model: previewModel(hidesBriefAwakes: true))
}

#Preview("Filter active (dark)") {
    ContentView(model: previewModel(hidesBriefAwakes: true))
        .preferredColorScheme(.dark)
}

#Preview("No filter") {
    ContentView(model: previewModel(hidesBriefAwakes: false))
}

#Preview("HealthKit not authorized") {
    ContentView(model: previewModel(hidesBriefAwakes: false, isHealthKitAuthorized: false))
}

#endif
