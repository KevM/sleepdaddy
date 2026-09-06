import SwiftUI

/// A flat stage-coloured wash drawn behind the vitals lanes, with a rule at each stage
/// change.
///
/// Uses `SleepStage.themeColor`, the app-wide stage palette. A subtle pattern provides a
/// second cue because REM and Core become similar when their shared colors are faded into
/// a background. Gaps remain unpainted and do not imply unknown-stage sleep.
public struct StageBackgroundLane: View {
    let intervals: [NormalizedSleepInterval]
    let geometry: SleepTimelineGeometry

    @Environment(\.colorScheme) private var colorScheme

    public init(intervals: [NormalizedSleepInterval], geometry: SleepTimelineGeometry) {
        self.intervals = intervals
        self.geometry = geometry
    }

    /// The same semantic color used by the timeline, inspectors, exports, and app icon.
    public static func washColor(for stage: SleepStage, isDark: Bool) -> Color {
        guard stage != .inBed else { return .clear }
        return stage.themeColor.opacity(StageBackgroundSpans.washOpacity(isDark: isDark))
    }

    public var body: some View {
        Canvas { context, size in
            let layout = StageBackgroundSpans(intervals: intervals, geometry: geometry)

            let isDark = colorScheme == .dark
            for span in layout.spans {
                let rect = CGRect(x: span.startX, y: 0, width: span.width, height: size.height)
                context.fill(
                    Path(rect),
                    with: .color(Self.washColor(for: span.stage, isDark: isDark))
                )
                Self.drawPattern(
                    StageBackgroundSpans.pattern(for: span.stage),
                    in: rect,
                    context: &context,
                    color: .primary.opacity(0.10)
                )
            }

            for x in layout.transitions {
                var rule = Path()
                rule.move(to: CGPoint(x: x, y: 0))
                rule.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(rule, with: .color(.primary.opacity(0.25)), lineWidth: 1)
            }
        }
        // The stages are already fully described by the canvas's chronological interval
        // list; repeating them here would only lengthen the VoiceOver pass over the night.
        .accessibilityHidden(true)
    }

    static func drawPattern(
        _ pattern: StageBackgroundSpans.Pattern,
        in rect: CGRect,
        context: inout GraphicsContext,
        color: Color,
        spacing: CGFloat = 18
    ) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            switch pattern {
            case .solid, .none:
                break
            case .horizontal:
                for y in stride(from: rect.minY + spacing / 2, through: rect.maxY, by: spacing) {
                    var path = Path()
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    layer.stroke(path, with: .color(color), lineWidth: 1)
                }
            case .diagonal, .crosshatch:
                for offset in stride(from: -rect.height, through: rect.width, by: spacing) {
                    var path = Path()
                    path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
                    layer.stroke(path, with: .color(color), lineWidth: 1)
                    if pattern == .crosshatch {
                        var reverse = Path()
                        reverse.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
                        reverse.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
                        layer.stroke(reverse, with: .color(color), lineWidth: 1)
                    }
                }
            case .dots:
                for x in stride(from: rect.minX + spacing / 2, through: rect.maxX, by: spacing) {
                    for y in stride(from: rect.minY + spacing / 2, through: rect.maxY, by: spacing) {
                        layer.fill(
                            Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                            with: .color(color)
                        )
                    }
                }
            }
        }
    }
}
