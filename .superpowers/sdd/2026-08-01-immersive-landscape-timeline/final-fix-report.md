# Immersive Landscape Timeline — Final Fix Wave

Date: 2026-08-01

Branch: `landscape-fixes`

Starting commit: `0c7f082` (`test: assert immersive landscape routing`)

## Outcome

All final-review findings were addressed within the immersive landscape timeline scope:

- Hosted landscape tests now resolve and assert the timeline's actual post-frame bounds. Both regular and accessibility hosted compositions reported `(x: 0, y: 54, width: 852, height: 220)` and assert `height >= 220`.
- Hosted tests semantically report the rendered header presentation. Both loaded landscape variants assert `.timelineOverlay`.
- Timeline pan recognition now begins only for predominantly horizontal velocity. Vertical, equal-diagonal, and stationary motion are rejected before the timeline recognizer begins, leaving vertical drags available to the enclosing scroll view.
- Accessibility coverage asserts that the accessibility overlay header remains at least 74 points tall and is fully contained by the timeline. The measured bounds were `(x: 84, y: 58, width: 684, height: 93.6667)`.
- A loaded, hosted portrait test asserts `.standard` layout with a `.standalone` header.
- The immersive empty-night test now hosts the real `ContentView` route and asserts a `.standalone` navigation header with a non-collapsed bound instead of inferring header presence from raster height.
- The final unfiltered suite and simulator build both succeeded.

## Investigation and root causes

### 1. The test preference flow stopped before rendered geometry

Trace:

1. `ContentView` resolves `SelectedNightLayoutMode` from `verticalSizeClass` and passes it to `SelectedNightDetailView`.
2. `SelectedNightDetailView.timelineCanvas` emitted only `SelectedNightTimelineLayoutPreferenceKey`, before the immersive branch applied `.frame(height:)` to the returned canvas composition.
3. `assertHostedComposition` observed only that layout-mode preference through `overlayPreferenceValue`.
4. The hosted tests then rasterized and asserted the outer `852 x 393` window (`1704 x 786` pixels), which says nothing about the child timeline height or header variant.

Hypothesis: an anchor preference attached after the composition-specific timeline frame would expose the real settled bounds without altering layout. Header presentation and bounds need equivalent semantic preference signals from `NightHeaderView`.

Evidence: after adding those preferences, the real hosted compositions reported a 220-point timeline in both landscape cases, `.timelineOverlay` headers, a 93.6667-point accessibility header, `.standard`/`.standalone` in portrait, and `.standalone` for the immersive empty-night route. Removing only the immersive bounds anchor made both hosted landscape tests fail because `metrics.timelineBounds` was `nil`.

### 2. The timeline pan entered recognition for vertical drags

Trace:

1. `TimelineGestureOverlay.makeUIView` installs a `UIPanGestureRecognizer` whose delegate is `Coordinator`.
2. `Coordinator` had no `gestureRecognizerShouldBegin`, so it admitted every pan direction.
3. `shouldRecognizeSimultaneouslyWith` returns `true` only for the timeline's pan/pinch pair. A timeline pan and an ancestor scroll-view pan are both pan recognizers and therefore do not recognize simultaneously.
4. Once the overlay pan begins for a vertical drag, UIKit can prevent the enclosing scroll-view pan, defeating the immersive vertical-scroll fallback over the plot.

Hypothesis: reject the overlay pan at UIKit's begin-decision boundary unless `abs(velocity.x) > abs(velocity.y)`. This leaves vertical and ambiguous motion to the scroll view while retaining horizontal timeline pan and existing pan/pinch simultaneity.

Evidence: a pure policy test covers horizontal, vertical, equal-diagonal, and zero velocity. A focused UIKit bridge test uses a pan recognizer with controlled velocity to prove the coordinator rejects vertical motion, accepts horizontal motion, and leaves pinch admission unchanged. Mutating the policy to always return `true` caused four expected failures across the policy and coordinator tests.

## TDD evidence

### RED

Tests were written before production changes.

Command:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineGestureSessionTests -only-testing:SleepDaddyTests/SnapshotTests/loadedLandscapeKeepsImmersiveTimeline -only-testing:SleepDaddyTests/SnapshotTests/loadedLandscapeAccessibilityKeepsImmersiveTimeline -only-testing:SleepDaddyTests/SnapshotTests/loadedPortraitUsesStandardComposition -only-testing:SleepDaddyTests/SnapshotTests/immersiveEmptyNightUsesStandaloneNavigationHeader
```

Result: exit 65, `** TEST FAILED **`. Compilation failed for the intended absent contracts:

- `cannot find 'SelectedNightTimelineBoundsPreferenceKey' in scope`
- `cannot find 'NightHeaderPresentationPreferenceKey' in scope`
- `cannot find 'NightHeaderBoundsPreferenceKey' in scope`
- `cannot find 'TimelinePanDirectionPolicy' in scope`
- `TimelineGestureOverlay.Coordinator` had no `gestureRecognizerShouldBegin`

### GREEN

The same focused command succeeded after the minimal implementation. Swift Testing's exact snapshot-function selectors did not execute those async snapshot cases in this environment, while the gesture suite did execute 7 tests, so the complete snapshot suite was then run explicitly:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

Result: exit 0, 20 tests in 1 suite passed, `** TEST SUCCEEDED **`. This run executed both hosted landscape tests, the new hosted portrait test, and the semantic empty-night test.

A diagnostic run of the same suite temporarily logged the resolved anchors:

- regular landscape timeline: `(0.0, 54.0, 852.0, 220.0)`
- regular landscape overlay header: `(84.0, 58.0, 684.0, 56.3333)`
- accessibility landscape timeline: `(0.0, 54.0, 852.0, 220.0)`
- accessibility overlay header: `(84.0, 58.0, 684.0, 93.6667)`
- portrait timeline: `(0.0, 138.6667, 393.0, 558.0)` with `.standard` / `.standalone`
- immersive empty-night header: `(0.0, 19.3333, 852.0, 60.3333)` with `.standalone`

The temporary logging was removed; the bound and semantic assertions remain.

### Mutation checks

Directional-pan mutation:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/TimelineGestureSessionTests
```

With the policy temporarily changed to admit every pan, result was exit 65 with 4 issues: the three rejecting pure-policy expectations and the coordinator's vertical-pan expectation failed. The implementation was restored.

Timeline-reporting mutation:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/SnapshotTests
```

With only the immersive post-frame anchor removed, result was exit 65. `loadedLandscapeKeepsImmersiveTimeline` and `loadedLandscapeAccessibilityKeepsImmersiveTimeline` both failed because the actual timeline bounds were `nil`. The anchor was restored.

## Final verification

Full unfiltered suite on the restored final implementation tree:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Result: exit 0, 109 tests in 14 suites passed, `** TEST SUCCEEDED **`.

Simulator build:

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Result: exit 0, `** BUILD SUCCEEDED **`.

The build emitted the existing App Intents metadata note (`Metadata extraction skipped, no AppIntents.framework dependency found`) and simulator/runtime diagnostics; there were no compiler errors or test failures.

`git diff --check` also completed with no whitespace errors.

## Files changed

- `SleepDaddy/Layout/TimelineGestureSession.swift`
  - Adds the pure horizontal-dominance pan admission policy.
- `SleepDaddy/Views/TimelineGestureOverlay.swift`
  - Bridges the policy through `gestureRecognizerShouldBegin`.
- `SleepDaddy/Views/ContentView.swift`
  - Defines the anchored timeline-bounds preference.
- `SleepDaddy/Views/SelectedNightDetailView.swift`
  - Emits timeline bounds after the standard/immersive composition frame is applied.
- `SleepDaddy/Views/NightHeaderView.swift`
  - Makes `Presentation` equatable and emits semantic presentation plus anchored bounds.
- `SleepDaddyTests/TimelineGestureSessionTests.swift`
  - Adds pure policy and UIKit delegate integration coverage.
- `SleepDaddyTests/SnapshotTests.swift`
  - Captures hosted timeline/header semantics and bounds; strengthens landscape, accessibility, portrait, and empty-night coverage.
- `.superpowers/sdd/2026-08-01-immersive-landscape-timeline/final-fix-report.md`
  - Records this investigation and verification.

## Self-review

- The pan change is isolated to recognizer admission. Pan updates, inertia, tap, pinch, and the existing simultaneous pan/pinch session remain unchanged.
- Strict horizontal dominance intentionally sends equal-diagonal and zero/ambiguous motion away from the timeline pan; this favors the vertical scroll fallback and avoids unstable ties.
- Anchor preferences are observational only and are attached after the relevant frame modifiers, so they do not affect rendered geometry.
- Landscape tests independently require `.immersiveLandscape`, timeline height `>= 220`, and `.timelineOverlay`; outer bitmap dimensions alone can no longer satisfy them.
- Accessibility coverage uses a minimum and containment contract rather than a pixel baseline. It tolerates larger future font metrics while catching a collapsed/clipped overlay container.
- The portrait test hosts the changed `ContentView` route instead of a legacy hand-built composite.
- The empty-night test hosts the compact `ContentView` route and observes `.standalone` directly; no raster-height inference remains.
- No HealthKit write behavior, sleep geometry, export rendering, filtering, toolbar behavior, generated project files, or unrelated files were changed.
- Pre-existing untracked files under `.claude/` and the unrelated 2026-07-29 plan/spec files were preserved and not staged.

## Unresolved concerns

- The gesture integration test exercises the real coordinator/delegate bridge with a controlled UIKit pan recognizer, but it is not a full UI automation of a finger drag through a nested `UIScrollView`. The pure policy plus delegate test is proportionate to the repository's unit-level gesture architecture.
- The accessibility contract verifies semantic presentation, non-collapsed height, and containment. It deliberately does not use brittle glyph-level pixel comparison, so it cannot prove every future OS font renderer's internal glyph clipping behavior.
- Exact Swift Testing function selectors did not execute the async hosted snapshot cases in this Xcode environment; the whole `SnapshotTests` suite and the final unfiltered suite are the authoritative execution evidence.
