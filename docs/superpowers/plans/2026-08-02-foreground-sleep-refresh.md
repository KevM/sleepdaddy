# Foreground Sleep Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh HealthKit sleep data whenever an already-running SleepDaddy scene becomes active.

**Architecture:** `ContentView` observes SwiftUI's `scenePhase` with one cancellable `.task(id:)` and forwards changes to `NightBrowserModel`. The model owns the active-only refresh decision, preserves valid navigation state during silent refreshes, and rejects overlapping loads.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing

## Global Constraints

- Keep HealthKit access read-only.
- Reuse `NightBrowserModel.loadData()` for authorization, querying, assembly, and newest-night selection.
- Do not add timers, background delivery, observer queries, dependencies, or manual controls.

---

### Task 1: Refresh on scene activation

**Files:**
- Modify: `SleepDaddy/ViewModels/NightBrowserModel.swift`
- Modify: `SleepDaddy/Views/ContentView.swift`
- Test: `SleepDaddyTests/NightBrowserModelTests.swift`

**Interfaces:**
- Consumes: `NightBrowserModel.loadData() async` and SwiftUI `ScenePhase`.
- Produces: `NightBrowserModel.handleScenePhaseChange(_ scenePhase: ScenePhase) async`.

- [x] **Step 1: Write the failing test**

Add tests that load an older fixture interval, introduce a newer night, invoke `handleScenePhaseChange(.active)`, and assert that the new data appears while the selected date, viewport, and inspected interval remain unchanged. Add controlled-store tests for silent refresh, load re-entrancy, and inactive/background phases.

- [x] **Step 2: Run the focused test to verify it fails**

Run:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/NightBrowserModelTests/sceneActivationRefreshesNewSleepData
```

Expected: compilation fails because `handleScenePhaseChange` does not exist.

- [x] **Step 3: Write the minimal implementation**

Add this model method:

```swift
@MainActor
public func handleScenePhaseChange(_ scenePhase: ScenePhase) async {
    guard scenePhase == .active else { return }
    await loadData()
}
```

Read `scenePhase` in `ContentView` with `@Environment(\.scenePhase)` and forward it from one `.task(id: scenePhase)`. Preserve navigation and loaded UI state on refresh, guard against overlapping loads, and avoid no-op `selectedDate` assignments.

- [x] **Step 4: Verify focused and complete tests**

Run the focused test, the complete `SleepDaddyTests` suite, and the standard simulator build. All must pass.

- [x] **Step 5: Commit**

Stage only the model, view, test, and this implementation plan, then commit with `fix: refresh sleep data on foreground`.
