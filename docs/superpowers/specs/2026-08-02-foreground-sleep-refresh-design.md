# Foreground Sleep Refresh Design

## Problem

SleepDaddy queries HealthKit when `ContentView` first appears, but does not query again when an already-running app returns to the foreground. Sleep data added while the app is backgrounded therefore remains invisible until the process is terminated and relaunched.

## Design

`ContentView` will observe SwiftUI's `scenePhase` with one cancellable `.task(id:)`. The task handles both initial appearance and later lifecycle transitions. Whenever the scene is `.active`, the view will ask `NightBrowserModel` to reload its data through the existing HealthKit authorization, fetch, normalization, and night-assembly path.

Initial loading will use the existing loading state. Once data is loaded, foreground refreshes will keep the loaded content visible and preserve the selected night, viewport, and inspected interval while the selection remains in the rebuilt overview window. Newly imported data will appear in the available nights without interrupting the user's current navigation. Background and inactive transitions will not fetch, and overlapping activation events will share the existing in-flight load.

No HealthKit background delivery, observer queries, timers, or manual refresh controls are added.

## Data Flow

1. The app scene becomes active.
2. `ContentView` receives the scene-phase change.
3. `NightBrowserModel.loadData()` requests authorization and fetches the current date-relative range.
4. The model replaces its cached intervals and available sources and reassembles the 14-night window without resetting a valid current selection.
5. SwiftUI renders the refreshed state.

## Error Handling

Foreground refresh uses the model's existing unavailable, unauthorized, and error states. The existing retry controls remain available if a refresh fails.

## Verification

- Add model regression tests that verify new data appears without changing a valid selection, navigation state survives refresh, loaded content remains visible, overlapping loads are rejected, and inactive/background phases do not fetch.
- Run the focused model tests, then the complete unit test suite.
- Build the app for the configured iPhone simulator destination.
