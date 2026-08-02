# Combined Timeline Rail Design

**Project:** SleepDaddy  
**Scope:** Portrait and landscape selected-night timelines  
**Status:** Approved

## Summary

SleepDaddy currently presents two time legends around the selected-night timeline: adaptive labels for the visible viewport inside the main canvas, plus configured timeline and core-window labels beneath a separate context navigator. The separate navigator composition consumes substantial vertical space, especially in landscape.

Replace the separate navigator row with a compact time rail at the bottom of the timeline canvas. The rail keeps the adaptive labels for the currently visible viewport and places an unlabeled minimap directly beneath them. The sleep-configuration legend is removed. This treatment is shared by portrait and landscape.

## Goals

- Preserve adaptive time labels for the currently visible viewport.
- Preserve the minimap as a sense-of-place aid while zoomed.
- Preserve minimap tap-to-recenter and drag-to-pan interactions.
- Remove the visually redundant configured timeline, core-window, and extended-range labels.
- Reclaim the separate navigator row's vertical space for the sleep-stage plot.
- Use one consistent presentation in portrait and landscape.
- Preserve accessible full-night context even when it is no longer printed visually.

## Non-Goals

- Changing pinch, pan, inertia, or viewport clamping behavior.
- Changing configured sleep windows or adaptive night assembly.
- Changing stage data, summary calculations, or source filtering.
- Overlaying controls on top of sleep-stage data.

## Presentation

The combined time rail is aligned with the plot region, excluding the fixed leading stage-label column. It contains two compact rows:

1. The existing adaptive major-tick labels for the currently visible viewport.
2. A visually thin full-night minimap with the current viewport handle.

The minimap does not display timeline start/end times, the core-window range, or an `Extended` marker. Those values describe configuration rather than the user's currently viewed area and are not needed in this compact presentation.

The rail remains below the sleep-stage plot instead of overlaying it. This preserves every stage lane and avoids gesture competition with interval selection and direct timeline panning.

The combined rail reserves 44 points at the bottom of the canvas. Its upper portion contains the adaptive labels; its lower portion centers a 10-point minimap track inside the remaining interactive region. The full rail is the minimap's touch target. Compared with the current 28-point canvas axis plus 64-point external navigator, this reduces the total time-navigation treatment from 92 to 44 points and returns 48 points to the stage plot.

## Interaction and Data Flow

The existing timeline remains the source of truth for the committed viewport. During direct interaction, `TimelineViewportPresentation` supplies the live viewport so the minimap handle follows pinch and pan movement immediately.

The combined rail reuses `SleepTimelineGeometry` for:

- adaptive visible-window ticks and label placement;
- mapping full-night dates to minimap positions;
- translating minimap drags into viewport changes; and
- recentering the viewport after a minimap tap.

The rail reports viewport changes through the existing callback path to `NightBrowserModel`. No model or persistence changes are required.

## Composition Changes

- `SleepTimelineCanvas` owns or composes the combined time rail because the rail shares its plot alignment and time-label geometry.
- `SelectedNightDetailView` no longer places `SlimContextNavigator` below the canvas in either standard or immersive landscape layout.
- Immersive landscape no longer subtracts a fixed 64-point navigator reservation when calculating timeline height.
- The reclaimed space expands the timeline plot in both orientations.
- Navigator drawing and gesture handling remain in a focused view or helper rather than enlarging the canvas body with a second independent implementation.

## Accessibility

The minimap remains exposed as one timeline-navigator accessibility element. Its spoken label includes the full navigable timeline start and end, even though those labels are removed visually. Its hint explains that the user can adjust the visible time range.

The current-view time labels remain visual annotations and do not replace the chronological interval accessibility elements already exposed by the timeline. Dynamic Type must not cause labels or the minimap to overlap the stage plot; the existing capped timeline label sizing remains applicable.

## Testing

### Geometry and interaction

- Retain the existing unit tests for navigator drag translation and tap recentering.
- Retain time-tick and time-label collision tests.
- Add focused coverage only if combining the rail introduces new layout calculations.

### Composition

- Verify the combined time rail is present in portrait and immersive landscape.
- Verify the separate navigator row is absent in both layouts.
- Verify current-view time labels remain present.
- Verify the minimap renders without its former start, core-window, end, and extended labels.
- Update landscape height assertions to reflect removal of the fixed 64-point reservation.
- Preserve light, dark, Dynamic Type, and Reduce Motion composition coverage.

### Manual verification

- Pinch and pan the timeline and confirm the minimap handle follows the live viewport.
- Tap outside the minimap handle and confirm the viewport recenters without changing duration.
- Drag the minimap handle and confirm the viewport moves proportionally across the full night.
- Confirm timeline interval selection and panning remain usable near the bottom stage lane.
- Confirm both orientations devote the reclaimed space to the sleep-stage plot.

## Acceptance Criteria

- Portrait and landscape show one combined time rail beneath the stage plot.
- Adaptive labels describe the currently visible viewport.
- The minimap remains visible, unlabeled, and interactive.
- No configured timeline/core-window legend is visually displayed.
- No separate navigator row consumes layout height.
- Full-night navigator context remains available to assistive technologies.
- Existing timeline and navigator gestures behave as before.
