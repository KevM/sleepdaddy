# Vitals chart and event navigation

Approved in conversation: preserve the continuous stage background shading, remove the redundant stage ribbon and inline key disclosure. Put SpO₂ and Pulse labels above their full-width plots. The key opens a scrollable sheet with vertically stacked, wrapping entries at the user's Dynamic Type size.

Tapping a marked oxygen event selects it and reveals a bottom overlay without resizing the chart. The panel has a wrapping description (position, time, duration, minimum oxygen), dismissal, and large Previous/Next controls. At accessibility text sizes controls may stack when necessary. Navigation keeps the current zoom and centers the event, clamped at night boundaries. Panning does not dismiss the panel. Closing or changing nights clears selection. Only events represented by the rail participate. Interactive controls are absent from static exports.

Use the existing gesture overlay to distinguish event taps from stage inspection. Provide accessible event actions as well as enlarged visual hit targets. Preserve the shared time geometry and overview rail. Verify at large and maximum accessibility sizes, plus the existing unit suite.

Follow-up clarification: the background must preserve Awake, REM, Deep, Core, and Unknown (asleepUnspecified), not collapse sleep stages. `SleepStage.themeColor` remains the app-wide source of truth; the background must not introduce alternate hues. Because fading makes Core and REM hard to distinguish, each stage also receives a subtle, stable pattern that is repeated in the chart key. No-data gaps remain blank. At large type, navigation labels fall back to accessible arrow buttons in one row; details scroll and dismissal stays visible. Short charts scroll vertically without shrinking the text.
