# Live Timeline Navigator Feedback

## Problem

During a chart pinch or drag, `SleepTimelineCanvas` renders its private live viewport while
`SlimContextNavigator` continues rendering the last viewport committed to
`NightBrowserModel`. The navigator catches up when the gesture ends, but the delay makes the
two linked controls appear disconnected.

## Design

`SelectedNightDetailView` will own a temporary optional live viewport for the active chart
gesture. `SleepTimelineCanvas` will report its current viewport whenever its interaction
controller changes it and will clear that temporary value when the gesture ends or is
cancelled. The detail view will pass the live viewport to `SlimContextNavigator` when one is
present and otherwise pass the model's committed viewport.

The model remains the durable source of truth. It is updated only with the settled viewport
at gesture completion, preserving clamping, reduced-motion behavior, and inertial settling.
Navigator-originated drags will continue updating the model through their existing path.

Both chart pinches and chart drags will publish live feedback. This keeps the navigator
indicator synchronized for every chart gesture without duplicating interaction rules.

## Component Changes

- `SleepTimelineCanvas` gains a live-viewport callback separate from its existing settled
  viewport callback.
- `SelectedNightDetailView` stores the temporary viewport and selects it for navigator
  rendering while a chart gesture is active.
- `SlimContextNavigator` remains a presentation and direct-manipulation component; its
  viewport interface does not change.

The chart must not feed each live update into `NightBrowserModel`: the chart currently
observes model viewport changes as external changes and cancels its interaction controller.
Keeping transient state above the two views, but outside the model, avoids that feedback
loop.

## Lifecycle and Edge Cases

- Gesture begin starts live reporting from the committed viewport.
- Pinch and pan changes replace the temporary viewport with the controller's current value.
- Gesture end commits the settled viewport and clears temporary state.
- A selected-night change or external viewport change clears stale temporary state.
- Temporary pan overscroll may be shown in the chart, but the navigator indicator uses the
  same viewport mapping and the final committed viewport remains clamped.
- Reduce Motion continues to disable inertial animation; it does not disable live navigator
  feedback.

## Testing

Add focused tests around the coordination state used by the detail view:

1. A live chart update becomes the viewport displayed by the navigator.
2. Clearing live interaction falls back to the committed model viewport.
3. A newly committed viewport is used after the live value is cleared.

Run the affected unit tests, the complete test suite, and the standard simulator build.

## Stage Stroke Weight

Increase the visual weight of the timeline stages to more closely match the supplied Apple
Health reference:

- Regular horizontal stage segments increase from 6 points to 10 points.
- Vertical transition connectors increase from 4 points to 6 points so they remain
  subordinate to the stage segments.
- Selected-stage emphasis increases its white outline from 10 points to 14 points and its
  colored center from 6 points to 10 points.

Stroke thickness remains fixed in screen points as the viewport zooms. This preserves a
stable visual hierarchy while zoom changes duration-to-pixel mapping. Existing snapshot
fixtures will be rendered and reviewed for intentional reference updates.

## Unspecified Sleep Presentation

The timeline always displays the four semantic rows Awake, REM, Core, and Deep.
`.asleepUnspecified` no longer creates a fifth row. Instead, each unspecified interval is
drawn in its existing muted-violet theme color as a rounded rectangle spanning the full
vertical area occupied by REM, Core, and Deep.

This treatment communicates that the person was asleep while the specific stage is unknown;
it does not visually claim an additional sleep depth. Transitions into and out of an
unspecified interval connect at the vertical center of the spanning band. Tapping anywhere
inside the band selects the underlying unspecified interval, and selected emphasis outlines
the entire band. Accessibility and inspector copy continue identifying the interval as
"Asleep (Unspecified)."

The spanning shape uses the existing `.asleepUnspecified` color. Its fill may use enough
opacity to retain row guidance underneath, while its selection outline remains clearly
visible. In-bed backgrounds and specific-stage strokes retain their existing behavior.

## Edge Tick Labels

Major time labels remain centered on their ticks when enough horizontal room exists. At the
leading and trailing plot edges, the canvas measures the rendered label and clamps its
center X coordinate between half the label width and the canvas width minus half the label
width. This keeps the complete time visible inside the clipped plot without permanently
insetting the timeline or changing interior tick alignment.

The clamping calculation belongs in `SleepTimelineGeometry` as a pure helper so leading,
interior, trailing, and labels wider than the canvas can be unit tested independently of
SwiftUI rendering. The canvas remains responsible for measuring resolved text and passing
the measured width into that helper.

## Loaded-State Vertical Alignment

The loaded-state content fills the available navigation content area and aligns its children
to the top. This keeps `NightHeaderView`, the divider, and `SelectedNightDetailView` directly
below the navigation bar whether the selected night has timeline data, an empty-state card,
or transient loading content.

The alignment belongs on the loaded-state container in `ContentView`, not inside the empty
card. The root cause is that the loaded container collapses to intrinsic height when its
detail has no flexible timeline, after which the outer full-height container centers the
whole group. A bottom spacer or empty-card-specific offset would hide that symptom while
leaving the parent layout inconsistent.

Add a loaded empty-night snapshot at a phone-sized viewport to protect the header’s top
position and the empty card’s relationship to it. Existing populated-night layouts remain
unchanged.
