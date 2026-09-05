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

    /// Low enough that the envelope always reads as the foreground, high enough that the
    /// darker stages stay apart from one another.
    ///
    /// Higher on dark: four of the six stage colours are already dark, so against a near
    /// black ground the same alpha that separates them on white collapses core, deep and
    /// REM into one blue-grey. Checked against a full night of real recording at both
    /// zoom levels.
    private static let washOpacity: Double = 0.14
    private static let darkWashOpacity: Double = 0.24

    /// The one pair the wash cannot separate by weight alone is awake's coral against a
    /// warning-amber column, both warm. Awake is carried lighter so the warm signal in the
    /// lane stays the reading rather than the background.
    private static let awakeWashOpacity: Double = 0.10
    private static let darkAwakeWashOpacity: Double = 0.17

    public init(intervals: [NormalizedSleepInterval], geometry: SleepTimelineGeometry) {
        self.intervals = intervals
        self.geometry = geometry
    }

    private var washOpacity: Double {
        colorScheme == .dark ? Self.darkWashOpacity : Self.washOpacity
    }

    private var awakeWashOpacity: Double {
        colorScheme == .dark ? Self.darkAwakeWashOpacity : Self.awakeWashOpacity
    }

    public var body: some View {
        Canvas { context, size in
            let layout = StageBackgroundSpans(intervals: intervals, geometry: geometry)

            for span in layout.spans {
                let opacity = span.stage == .awake ? awakeWashOpacity : washOpacity
                context.fill(
                    Path(CGRect(x: span.startX, y: 0, width: span.width, height: size.height)),
                    with: .color(span.stage.themeColor.opacity(opacity))
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
