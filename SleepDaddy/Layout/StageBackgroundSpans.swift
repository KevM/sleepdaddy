import CoreGraphics
import Foundation

/// The stage wash drawn behind the vitals lanes, resolved to x coordinates.
///
/// Answers "what stage was I in when this dip happened, and did it start at a stage
/// change" by putting the stage under the reading rather than a lane away from it. The
/// x axis comes from the same `SleepTimelineGeometry` the stage plot uses, so the wash
/// cannot drift out of alignment with the plot above it through pinch and pan.
///
/// `.inBed` is dropped because `SleepTimelineGeometry.stepSegments` drops it: tinting a
/// stretch the plot leaves blank would assert a stage the timeline does not show.
///
/// Transitions are carried separately because the wash alone cannot show them. Adjacent
/// stages are frequently both blue — core against REM — and at wash opacity their shared
/// edge is invisible, which would answer the "states" half of the question and silently
/// fail the "transitions" half.
public struct StageBackgroundSpans: Equatable, Sendable {
    public struct Span: Equatable, Sendable {
        public let stage: SleepStage
        public let startX: CGFloat
        public let endX: CGFloat

        public var width: CGFloat { endX - startX }
    }

    /// Visible, clipped, wide-enough stage bands, in time order.
    public let spans: [Span]

    /// X positions where one stage abuts a different stage, in time order.
    public let transitions: [CGFloat]

    /// Narrower than a point, a band reads as a hairline of stray colour rather than as a
    /// stage, so it is dropped instead of drawn.
    private static let minimumVisibleWidth: CGFloat = 0.5

    /// Matches the tolerance `stepSegments` uses to decide two intervals touch.
    private static let abuttingTolerance: TimeInterval = 0.001

    /// The stages the wash actually paints, once each, in timeline row order.
    ///
    /// Derived from the same `.inBed` rule the wash uses, so the legend cannot come to
    /// name a colour that is not on screen. `SleepStage.allCases` is already in row order,
    /// which is the order the stage plot stacks its rows in, so the chips read down the
    /// plot rather than in order of first appearance.
    public static func legendStages(in intervals: [NormalizedSleepInterval]) -> [SleepStage] {
        let present = Set(intervals.map(\.stage))
        return SleepStage.allCases.filter { present.contains($0) && $0 != .inBed }
    }

    public init(intervals: [NormalizedSleepInterval], geometry: SleepTimelineGeometry) {
        let staged = intervals
            .filter { $0.stage != .inBed }
            .sorted { $0.startDate < $1.startDate }

        let leadingEdge = SleepTimelineGeometry.horizontalPlotInset
        let trailingEdge = max(leadingEdge, geometry.canvasWidth - leadingEdge)

        var spans: [Span] = []
        for interval in staged {
            let startX = min(max(geometry.xPosition(for: interval.startDate), leadingEdge), trailingEdge)
            let endX = min(max(geometry.xPosition(for: interval.endDate), leadingEdge), trailingEdge)
            guard endX - startX >= Self.minimumVisibleWidth else { continue }
            spans.append(Span(stage: interval.stage, startX: startX, endX: endX))
        }
        self.spans = spans

        // Read off the intervals rather than the spans: a boundary is a fact about the
        // night, not about which bands happened to survive clipping.
        var transitions: [CGFloat] = []
        for (previous, current) in zip(staged, staged.dropFirst()) {
            let gap = abs(current.startDate.timeIntervalSince(previous.endDate))
            guard gap < Self.abuttingTolerance, previous.stage != current.stage else { continue }
            let x = geometry.xPosition(for: current.startDate)
            guard x >= leadingEdge, x <= trailingEdge else { continue }
            transitions.append(x)
        }
        self.transitions = transitions
    }
}
