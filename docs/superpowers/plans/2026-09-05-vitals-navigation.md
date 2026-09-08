# Vitals Navigation Implementation Plan

**Goal:** Stable full-width vitals with stage shading and contextual event navigation designed for large text.

**Architecture:** Canvas owns selection and sheet presentation; VitalsLanesLayout budgets scaled headings independently of selection. SleepTimelineGeometry handles event hit testing and viewport centering. Separate views render the event panel and scrollable key.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, iOS 18+.

## Global Constraints

Preserve existing work on o2max_integration. HealthKit remains read-only. Do not commit generated project files. Preserve sleep-only timeline behavior and static export behavior.

- [x] Replace obsolete disclosure layout tests; add event hit-target and zoom-preserving boundary tests in SleepTimelineGeometryTests. Run the focused suite before implementation.
- [x] Replace VitalsLanesView's ribbon/key/label column with scaled above-plot headings and continuous stage shading. Use the same inset for envelopes, shading, events, and axis.
- [x] Add geometry event hit testing with a 44-point minimum target, excluding offscreen/unmarked events; add clamped date centering that preserves viewport duration.
- [x] Add a scrollable VitalsChartKeyView and wrapping VitalsEventPanel. Canvas handles event selection, previous/next endpoints, dismissal, night/session changes, and export interactivity.
- [x] Run the full unit suite and build; inspect the simulator at large text sizes. Request independent review, fix actionable findings, and report evidence.

Verification: temporary hosted-view fixtures inspected at accessibility2 and accessibility5, including key and dark mode. The fixture harness was removed after inspection. Tests cover hit-target filtering, viewport boundaries, and a unique redundant pattern for each stage while retaining the shared app-wide stage palette. Independent review found no actionable defects. Direct touch testing remains unverified because Simulator is not available through the UI-control surface.
