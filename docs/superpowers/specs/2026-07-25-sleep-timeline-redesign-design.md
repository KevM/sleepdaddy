# Sleep Timeline Redesign

## Goal

Replace the current delayed, card-heavy sleep viewer with a responsive, space-efficient timeline that behaves like a map: the content follows the user's fingers during pan and pinch, the zoom remains anchored beneath the pinch midpoint, and the full-night context is always recoverable without a Reset control.

The primary sleep visualization will be a continuous stepped path inspired by the visual grammar of Apple Health. Navigation, filtering, sharing, and date selection will be reduced to compact, purposeful controls.

## Current Problems and Root Causes

### Delayed gestures

`SleepTimelineCanvas` writes pinch scale and pan translation into transient state during `onChanged`, but rendering never reads either value. The viewport is recalculated and sent to the model only from `onEnded`. The frozen pinch and jumping pan are therefore deterministic consequences of the current data flow, not general rendering slowness.

### Incorrect initial night

`NightBrowserModel` sorts `assembledNights` in ascending chronological order, then uses `first(where: \.hasSleepData)` when loading. This selects the oldest populated night in the window. Startup must instead select the newest populated night.

### Clutter and unused space

The detail timeline has a fixed 280-point height inside a scrolling, card-heavy layout. The always-visible 14-night strip, source controls, duplicate toolbar branding, text-labeled Reset and Share buttons, and fixed canvas collectively consume space while leaving the lower screen visually underused.

## Visual Design

### Continuous sleep path

The primary sleep record is rendered as a continuous stepped path:

- Each sleep-stage interval is a horizontal colored segment at its stage height.
- Consecutive intervals are joined by vertical transition segments.
- Rounded joins and restrained stroke widths keep the path readable.
- `In Bed` is a subdued background band rather than an equal-weight stage row.
- Conflicts appear as faint overlays with a small warning marker. Selecting the affected time reveals full detail.
- Fixed stage labels remain at the leading edge while timeline content pans beneath them.
- A compact time axis remains visible and changes tick spacing with zoom level.

The timeline consumes the available vertical space. Stage lanes distribute through that space instead of being constrained to a fixed 280-point card. Larger devices and landscape layouts give the data more room rather than enlarging controls.

### Controls

- Remove the Reset button.
- Replace Share text with an icon-only action and an explicit accessibility label.
- Replace the always-visible source selector with one compact filter icon. A badge indicates an active filter; tapping the icon presents the full source list in a sheet.
- Remove the decorative leading moon and duplicate `SleepDaddy` toolbar label.
- Keep only actionable toolbar controls: filter, share, and settings.
- Reduce rounded-card chrome so the data, rather than its container, is the visual focus.

### Overview navigator

A slim overview near the bottom safe area shows the complete detected night and the current viewport. It prevents loss of context while using little vertical space.

## Night Navigation

Remove the always-visible multi-night card strip. Replace it with a compact, full-width header containing:

`‹  Friday, July 24 · 7h 42m  ›`

- The arrows move to the immediately older or newer night.
- A leftward swipe across the header moves to the next/newer night.
- A rightward swipe moves to the previous/older night.
- The entire header is the gesture target, allowing an easy edge-to-edge swipe without competing with timeline pan gestures below it.
- Tapping the date opens a compact calendar sheet for non-adjacent navigation.
- Navigation is constrained to assembled nights. The newer arrow is disabled on the newest available night, and the older arrow is disabled on the oldest.
- A night change uses a short directional transition, cancels active timeline interaction, clears stale interval selection, and fits the new night.
- On launch, select the newest assembled night containing eligible sleep data. If no assembled night contains sleep, select the expected previous-night window within the available range.

## Direct Manipulation

The timeline has one unified, live interaction state.

### Pan

- A one-finger drag pans continuously, with the content remaining under the finger.
- Releasing a sufficiently fast drag continues with short velocity-based deceleration.
- Movement beyond tap tolerance cancels interval selection.

### Pinch

- A two-finger pinch zooms continuously.
- Zoom is anchored to the live midpoint of the two touches. The date below that midpoint remains stationary as scale changes.
- Pan and pinch may occur simultaneously without restarting, snapping, or applying either transform twice.

### Bounds and recovery

- The maximum viewport is the complete detected night.
- The minimum viewport duration is five minutes.
- Panning and zooming past a full-night edge applies gentle resistance during the gesture, followed by a clean settle inside bounds.
- Pinching outward naturally returns to the full night. No reset action or hidden recovery state exists.
- Reduce Motion disables inertial continuation and uses minimal settling animation.

### Selection

A stationary tap selects the visible primary interval at that time. Selection uses the same live viewport and geometry as drawing. Conflicts associated with the selected time are presented in the existing inspector flow.

## Overview Interaction

- Dragging the viewport window pans continuously.
- Tapping outside the viewport recenters it around the tapped date.
- The viewport window, main timeline, time axis, and hit-testing all update from the same live viewport.
- The navigator always represents the complete detected night, independent of main timeline zoom.

## Architecture

### `TimelineViewport`

A small value type containing visible start and end dates. It exposes duration and validity but does not own UI state.

### `TimelineInteractionController`

Owns an active interaction session:

- baseline viewport at gesture start;
- live pan and magnification values;
- live pinch centroid;
- velocity;
- boundary resistance; and
- final settling.

It produces the live viewport used for rendering. Its math remains independent of SwiftUI views so it can be unit tested deterministically.

### `SleepTimelineGeometry`

Remains the pure geometry layer. It will handle:

- date/position conversion;
- viewport clamping;
- focal-point-preserving zoom;
- pan conversion;
- stepped-path coordinates;
- adaptive time ticks;
- interval and conflict hit-testing; and
- navigator coordinate conversion.

### `SleepTimelineCanvas`

Renders the stepped path, overlays, labels, and time axis from the live viewport. It forwards touch input to the interaction controller and commits only the settled viewport to the model. It must not keep transient gesture values that drawing does not consume.

If SwiftUI's high-level magnification gesture does not expose a reliable live centroid on the deployment target, the canvas may use a narrowly scoped UIKit gesture recognizer bridge for touch measurement while retaining the custom SwiftUI renderer and pure Swift interaction math. This is an implementation detail, not a switch to a scroll-view-based design.

### `NightHeaderView`

Owns previous/next buttons, formatted date and summary, the bounded horizontal swipe gesture, calendar presentation, navigation accessibility actions, and disabled states.

### `SlimContextNavigator`

Uses the same viewport and geometry types as the main canvas and reports continuous drag updates rather than only an end-state jump.

### `NightBrowserModel`

Owns selected night and the settled viewport. It does not receive every transient frame of a gesture. Startup chooses the newest populated night, and navigation methods enforce available-night bounds.

## Data Flow

1. The model supplies the selected night and settled viewport.
2. The interaction controller begins from that viewport.
3. Gesture changes produce a live viewport every frame.
4. The timeline, time axis, selection geometry, and navigator render from that live viewport.
5. Gesture completion settles bounds and inertia.
6. The final viewport is committed to the model.
7. Changing nights cancels the interaction session and initializes a full-night viewport.

## Accessibility

- Every icon-only action has an explicit label, hint where useful, and at least a 44-by-44-point hit target.
- The night header exposes previous and next accessibility actions in addition to buttons.
- Sleep intervals remain available in chronological VoiceOver order even though their visual vertical position represents stage.
- Stage identity is never conveyed by color alone; labels and interval descriptions remain available.
- Reduce Motion removes inertia and minimizes directional transitions.
- Dynamic Type must not cause toolbar controls or the date header to overlap; the summary may wrap or collapse to a shorter format when necessary.

## Verification

### Geometry and interaction tests

- Zoom preserves the anchor date at arbitrary centroid positions.
- Repeated live pinch updates are computed from a stable baseline and do not compound incorrectly.
- Simultaneous pan and pinch produce one combined transform.
- Full-night and five-minute limits clamp correctly.
- Resistance is temporary and the settled viewport is always valid.
- Pan velocity decelerates in the expected direction and terminates.
- Reduce Motion disables inertial continuation.
- Stepped path coordinates include the correct horizontal segments and vertical transitions.
- Adaptive tick spacing remains legible across supported zoom levels.
- Hit-testing uses the live viewport.
- Navigator drag and recenter math match the main viewport.

### Model and navigation tests

- Ascending assembled nights select the last populated night on startup.
- No-data startup selects the expected previous-night window.
- Previous and next navigation stop at available bounds.
- A night change fits the new night and clears transient interaction and stale selection.

### UI verification

- Update snapshot coverage for the new full-height layout and stepped path.
- Verify portrait, landscape, Dynamic Type, dark mode, VoiceOver, and Reduce Motion.
- On an iPhone simulator or device, confirm that pinch and pan visibly update before release, the pinch midpoint remains stable, inertia is brief and controllable, and the header swipe never interferes with timeline gestures.

## Acceptance Criteria

- The sleep path responds visually on every pan and pinch update.
- Pinching does not jump when it begins, changes touch position, or ends.
- One-finger panning feels direct and settles within night boundaries.
- The user can always return to the full night by pinching outward or using the overview; no Reset control exists.
- Consecutive primary sleep stages are visibly connected.
- The initial selection is the newest populated night, not the oldest.
- Adjacent nights are reachable through header buttons and a full-width header swipe.
- The persistent multi-night strip, persistent source list, decorative moon branding, and text-labeled Share control are absent.
- The timeline and overview use the available screen height without leaving a large unused lower region.
