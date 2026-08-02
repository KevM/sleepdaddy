# Foreground Sleep Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh HealthKit sleep data whenever an already-running SleepDaddy scene becomes active.

**Architecture:** `ContentView` observes SwiftUI's `scenePhase` and forwards changes to `NightBrowserModel`. The model owns the active-only refresh decision so the behavior can be tested without a UI inspection dependency.

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

Add a test that loads an older fixture interval, replaces the fixture store's intervals with a newer night, invokes `handleScenePhaseChange(.active)`, and asserts that the newer night becomes selected.

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

Read `scenePhase` in `ContentView` with `@Environment(\.scenePhase)` and forward changes from `.onChange(of: scenePhase)` in a `Task`.

- [x] **Step 4: Verify focused and complete tests**

Run the focused test, the complete `SleepDaddyTests` suite, and the standard simulator build. All must pass.

- [ ] **Step 5: Commit**

Stage only the model, view, test, and this implementation plan, then commit with `fix: refresh sleep data on foreground`.
