import SwiftUI

/// A flat stage-coloured wash drawn behind the vitals lanes, with a rule at each stage
/// change.
///
/// Uses `SleepStage.themeColor` rather than a palette of its own so the wash reads against
/// the stage plot directly above it, which is what lets it work without a second legend.
///
/// The wash shares hues with the SpO₂ zone colours — three of the six stages are in the
/// blue family, as is the normal SpO₂ band. They stay distinguishable through weight
/// rather than hue: the wash is flat and nearly transparent, the envelope solid and
/// saturated. Foreground and background at those weights are not confusable, which a
/// neutral lightness ramp would have bought at the cost of telling six stages apart.
///
/// Gaps are left unpainted on purpose: no wash means no stage data, not a stage of zero.
public struct StageBackgroundLane: View {
    let intervals: [NormalizedSleepInterval]
    let geometry: SleepTimelineGeometry

    @Environment(\.colorScheme) private var colorScheme

    public init(intervals: [NormalizedSleepInterval], geometry: SleepTimelineGeometry) {
        self.intervals = intervals
        self.geometry = geometry
    }

    /// The colour a stage band is washed in — one of two, per `washTone`. Awake keeps its
    /// coral; every sleeping stage shares core's blue, because the wash cannot carry more
    /// than that distinction and pretending otherwise showed four bands that were not
    /// actually distinguishable.
    public static func washColor(for stage: SleepStage, isDark: Bool) -> Color {
        let base: Color = StageBackgroundSpans.washTone(for: stage) == .awake
            ? SleepStage.awake.themeColor
            : SleepStage.core.themeColor
        return base.opacity(StageBackgroundSpans.washOpacity(isDark: isDark))
    }

    public var body: some View {
        Canvas { context, size in
            let layout = StageBackgroundSpans(intervals: intervals, geometry: geometry)

            let isDark = colorScheme == .dark
            for span in layout.spans {
                context.fill(
                    Path(CGRect(x: span.startX, y: 0, width: span.width, height: size.height)),
                    with: .color(Self.washColor(for: span.stage, isDark: isDark))
                )
            }

            for x in layout.transitions {
                var rule = Path()
                rule.move(to: CGPoint(x: x, y: 0))
                rule.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(rule, with: .color(.primary.opacity(0.25)), lineWidth: 1)
            }
        }
        // The same stages are already fully described by the stage plot above; repeating
        // them here would only lengthen the VoiceOver pass over the vitals.
        .accessibilityHidden(true)
    }
}
