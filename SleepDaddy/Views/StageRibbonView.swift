import SwiftUI

/// A thin, fully saturated stage strip beneath the vitals lanes.
///
/// Carries exact stage identity, which the wash above it cannot. Nothing is drawn over
/// the ribbon, so it is free to use the stage plot's own colours at full strength and the
/// four stages separate easily — the constraint that defeated a four-tone wash was having
/// to stay pale enough to sit behind the envelope.
///
/// Shares `StageBackgroundSpans` with the wash, so ribbon and wash are the same spans at
/// the same x positions and cannot disagree about where a stage begins.
public struct StageRibbonView: View {
    let intervals: [NormalizedSleepInterval]
    let geometry: SleepTimelineGeometry

    public static let ribbonHeight: CGFloat = 8

    public init(intervals: [NormalizedSleepInterval], geometry: SleepTimelineGeometry) {
        self.intervals = intervals
        self.geometry = geometry
    }

    public var body: some View {
        Canvas { context, size in
            for span in StageBackgroundSpans(intervals: intervals, geometry: geometry).spans {
                context.fill(
                    Path(CGRect(x: span.startX, y: 0, width: span.width, height: size.height)),
                    with: .color(span.stage.themeColor)
                )
            }
        }
        .frame(height: Self.ribbonHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.ribbonHeight / 2))
        .accessibilityHidden(true)
    }
}
