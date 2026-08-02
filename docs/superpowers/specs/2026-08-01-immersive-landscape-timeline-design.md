# Immersive Landscape Timeline Design

## Problem

The selected-night screen spends too much of a phone's limited landscape height on the standalone night header, divider, and vertical padding. The sleep timeline is consequently short at regular Dynamic Type sizes and can collapse to nearly one row at accessibility sizes.

## Goals

- Make the sleep visualization the primary use of vertical space on phones in landscape.
- Keep the selected date, sleep duration, previous/next navigation, and date picker available.
- Preserve Dynamic Type support without allowing surrounding controls to collapse the timeline.
- Leave the existing portrait composition unchanged.
- Preserve the timeline's existing gestures, selection behavior, and context navigator.

## Responsive Composition

`ContentView` will choose its loaded-night composition from the vertical size class:

- In regular vertical size class, retain the current portrait structure: standalone `NightHeaderView`, divider, timeline, and context navigator.
- In compact vertical size class, use an immersive landscape structure. Remove the standalone header and divider from the vertical stack. Give the selected-night detail the full remaining content height.

The landscape navigation bar will replace the centered `SleepDaddy` title with a compact standalone date button. Selecting the date opens the existing date picker. A separate, non-interactive accent-colored duration label will sit beside the date button in the principal toolbar area; the duration is not part of the date button's label or hit target. Existing filter, share, and settings toolbar items remain unchanged.

Previous and next controls remain independent at the left and right edges of the timeline. They retain their disabled states, accessibility labels, and swipe navigation semantics without placing the date or duration over the visualization. The timeline itself has no header overlay.

The timeline will fill the available height, with the slim context navigator immediately below it. The timeline remains the flexible, highest-priority region; the navigator keeps only the space needed by its controls and labels.

At accessibility Dynamic Type sizes, toolbar content uses the system's toolbar layout behavior and the compact date format. If the entire landscape detail cannot fit at an extreme size, the detail region may scroll vertically, but the timeline receives a useful minimum height before scrolling is introduced. Text will not be globally capped as a substitute for responsive layout.

## Component Boundaries

- Extract shared night-navigation behavior so portrait and landscape variants cannot drift in date formatting, picker behavior, actions, or accessibility metadata.
- Keep landscape layout selection in the screen composition layer, not in timeline geometry or drawing code.
- Keep `SleepTimelineCanvas` focused on rendering and interaction. The fix must not change date-to-pixel geometry or sleep-stage data.
- Keep the empty-night and loading states functional in both size classes; they do not require the immersive overlay when no sleep timeline exists.

## Interaction and Accessibility

- Previous/next buttons retain 44-point hit targets.
- The selected date remains a button that opens the existing date picker.
- VoiceOver labels, hints, and custom previous/next actions remain equivalent to portrait.
- Dynamic Type remains enabled for the date and duration.
- Timeline gestures continue to work within the plot. Vertical drags remain available to the enclosing scroll view when accessibility content overflows.

## Testing

- Add a layout-focused test that fails under the current implementation and demonstrates that compact-height composition selects the immersive variant.
- Add hosted snapshot coverage for phone landscape at regular Dynamic Type.
- Add hosted snapshot coverage for phone landscape at an accessibility Dynamic Type size matching the reported failure.
- Assert that loaded landscape composition exposes the standalone toolbar date picker and separate duration label while the timeline retains at least 220 points of height.
- Assert that the timeline no longer reports a date-header overlay in landscape.
- Retain existing portrait and Dynamic Type snapshot coverage to catch regressions.
- Run the full Swift Testing suite using the project-standard iPhone 17 simulator destination.

## Out of Scope

- Redesigning the portrait screen.
- Changing sleep-stage geometry, colors, filtering, data loading, or export rendering.
- Moving settings, sharing, or source filtering out of the navigation toolbar.
- Supporting a new iPad-specific composition.
