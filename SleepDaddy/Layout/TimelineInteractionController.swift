import Foundation
import CoreGraphics

/// Turns the cumulative values reported by pan and pinch recognizers into a live viewport.
///
/// The controller keeps a `baselineViewport` fixed for the length of a gesture and
/// recomputes `liveViewport` from scratch on every update: magnification is applied to
/// the baseline first, then the pan translation. Because recognizers report *absolute*
/// values rather than deltas, feeding `liveViewport` back in as the next baseline would
/// compound every update and make the timeline drift away under the finger. Nothing here
/// touches SwiftUI or UIKit; it is a value type so a view can own one in `@State`.
///
/// ## Overscroll versus clamping
///
/// `SleepTimelineGeometry.zoomed` and `.panned` already clamp their results into the
/// night, but a Maps-style drag should stretch a little past the edge while the finger is
/// down. The controller therefore recomputes the *unclamped* pan proposal itself, measures
/// how far clamping pulled it back, and re-applies that excess through a damped rubber-band
/// curve. When a pan lands in bounds the excess is zero and `liveViewport` is exactly
/// `geometry.panned(...)`, so in-bounds behaviour stays identical to the geometry layer.
/// Resistance applies to panning only — over-pinching is still clamped outright by
/// `zoomed`, since a window that snaps back in size reads as a glitch rather than as slack.
public struct TimelineInteractionController: Sendable {
    /// The viewport to draw right now, including any temporary overscroll.
    public private(set) var liveViewport: TimelineViewport

    /// The viewport the current gesture started from. Never overwritten mid-gesture.
    private var baselineViewport: TimelineViewport
    private var panTranslationX: CGFloat = 0
    private var magnification: CGFloat = 1
    private var anchorX: CGFloat = 0

    /// Hard ceiling on overscroll, as a fraction of the visible window.
    static let overscrollLimitFraction: Double = 0.25

    /// How long a fling is projected to keep travelling after the finger lifts. A flick
    /// should coast far enough to feel weightless but land somewhere the eye followed,
    /// so this is deliberately shorter than a scroll view's long decelerating glide.
    ///
    /// Empirically tuned; safe to adjust without touching the surrounding math.
    static let inertiaProjectionDuration: TimeInterval = 0.25

    /// Ceiling on a projected fling, as a fraction of the canvas width. Caps a frantic
    /// swipe at half a screen of travel so the timeline never skips a stretch of the
    /// night entirely, which would cost the reader their place.
    ///
    /// Empirically tuned; safe to adjust without touching the surrounding math.
    static let inertiaLimitCanvasFraction: CGFloat = 0.5

    public init(viewport: TimelineViewport) {
        self.liveViewport = viewport
        self.baselineViewport = viewport
    }

    /// Starts a new gesture session from `viewport`, discarding any earlier pan or pinch.
    public mutating func begin(viewport: TimelineViewport) {
        reset(to: viewport)
    }

    /// Abandons the gesture in flight and snaps to `viewport`.
    ///
    /// Used when the selected night changes underneath an active gesture, where the
    /// in-flight transform belongs to a window that no longer exists.
    public mutating func cancel(viewport: TimelineViewport) {
        reset(to: viewport)
    }

    /// Applies the recognizer's cumulative horizontal translation.
    ///
    /// Dragging content to the left (a negative `translationX`) moves the viewport later in time.
    public mutating func updatePan(translationX: CGFloat, geometry: SleepTimelineGeometry) {
        panTranslationX = translationX
        recomputeLiveViewport(geometry: geometry)
    }

    /// Applies the recognizer's cumulative pinch scale about a canvas anchor.
    ///
    /// A magnification greater than 1 zooms in; the date under `anchorX` stays put.
    public mutating func updateMagnification(
        _ magnification: CGFloat,
        anchorX: CGFloat,
        geometry: SleepTimelineGeometry
    ) {
        self.magnification = magnification
        self.anchorX = anchorX
        recomputeLiveViewport(geometry: geometry)
    }

    /// Ends the gesture and returns the viewport to commit.
    ///
    /// Any overscroll is dropped: the result is always inside the night. With Reduce Motion
    /// off, a capped translation projected from `velocityX` is panned in first so a flick
    /// carries; with it on, the timeline simply stops where the finger left it.
    public mutating func settledViewport(
        geometry: SleepTimelineGeometry,
        velocityX: CGFloat,
        reduceMotion: Bool
    ) -> TimelineViewport {
        let inBounds = geometry.clamped(liveViewport)
        let settled = reduceMotion
            ? inBounds
            : geometry.panned(
                inBounds,
                deltaX: Self.projectedTranslation(velocityX: velocityX,
                                                  canvasWidth: geometry.canvasWidth)
            )
        reset(to: settled)
        return settled
    }

    private mutating func reset(to viewport: TimelineViewport) {
        baselineViewport = viewport
        liveViewport = viewport
        panTranslationX = 0
        magnification = 1
        anchorX = 0
    }

    private mutating func recomputeLiveViewport(geometry: SleepTimelineGeometry) {
        let zoomed = geometry.zoomed(baselineViewport,
                                     magnification: magnification,
                                     anchorX: anchorX)
        liveViewport = Self.panWithResistance(zoomed,
                                              translationX: panTranslationX,
                                              geometry: geometry)
    }

    /// Pans `baseline` by `translationX`, letting the part that clamping rejected bleed
    /// back in through a rubber-band curve.
    private static func panWithResistance(
        _ baseline: TimelineViewport,
        translationX: CGFloat,
        geometry: SleepTimelineGeometry
    ) -> TimelineViewport {
        let inBounds = geometry.panned(baseline, deltaX: translationX)
        let proposed = geometry.unclampedPanned(baseline, deltaX: translationX)

        // `panned` is defined as `clamped(unclampedPanned(...))`, so an in-bounds drag leaves
        // the two starts bit-identical and this excess is exactly zero by construction.
        let excess = proposed.start.timeIntervalSince(inBounds.start)
        guard excess != 0 else { return inBounds }

        let limit = overscrollLimitFraction * inBounds.duration
        return inBounds.shifted(by: rubberBanded(excess, limit: limit))
    }

    /// Damps `excess` along a curve that tracks it near zero and approaches, but never
    /// reaches, `limit`. Keeps a frantic drag from tearing the window off the night.
    private static func rubberBanded(_ excess: TimeInterval, limit: TimeInterval) -> TimeInterval {
        guard limit > 0 else { return 0 }
        let magnitude = abs(excess)
        let damped = limit * magnitude / (magnitude + limit)
        return excess < 0 ? -damped : damped
    }

    /// Converts a lift-off velocity in points per second into a capped extra translation.
    private static func projectedTranslation(velocityX: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        let limit = max(1.0, canvasWidth) * inertiaLimitCanvasFraction
        let projected = velocityX * CGFloat(inertiaProjectionDuration)
        return min(limit, max(-limit, projected))
    }
}
