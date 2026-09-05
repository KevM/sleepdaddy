import SwiftUI

/// Rail plus the two envelope lanes, beneath the stage plot and sharing its time axis.
///
/// Builds its own `SleepTimelineGeometry` from the same night and viewport as the stage
/// plot, and reserves the same leading label column, so both stay aligned. Because the
/// viewport lives in `NightBrowserModel`, pinch and pan on the canvas re-render these
/// lanes automatically — there is nothing to synchronise.
public struct VitalsLanesView: View {
    let session: VitalsSession
    let events: [DesaturationEvent]
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date

    /// Matches `SleepTimelineCanvas`'s stage-label column so the x axes line up.
    private static let labelWidth: CGFloat = 68
    private static let spo2LaneHeight: CGFloat = 56
    private static let pulseLaneHeight: CGFloat = 44
    private static let laneSpacing: CGFloat = 6

    /// Both envelope lanes and the gap between them, so the wash behind them is continuous.
    private static let washHeight: CGFloat = spo2LaneHeight + laneSpacing + pulseLaneHeight

    public init(
        session: VitalsSession,
        events: [DesaturationEvent],
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date
    ) {
        self.session = session
        self.events = events
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
    }

    public var body: some View {
        GeometryReader { proxy in
            let plotWidth = max(1, proxy.size.width - Self.labelWidth)
            let viewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
            let geometry = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: viewport,
                canvasWidth: plotWidth,
                canvasHeight: proxy.size.height
            )
            let envelope = VitalsEnvelopeBuilder().build(
                session: session,
                viewport: viewport,
                pixelWidth: Int(plotWidth.rounded())
            )

            VStack(alignment: .leading, spacing: Self.laneSpacing) {
                labelled("EVENTS") {
                    DesaturationRailView(events: events, geometry: geometry)
                }
                // One wash spanning both lanes, so a transition rule runs unbroken through
                // SpO₂ and pulse together and a dip can be lined up against it by eye.
                ZStack(alignment: .topLeading) {
                    StageBackgroundLane(
                        intervals: night.displayLaneIntervals, geometry: geometry
                    )
                    .frame(width: plotWidth, height: Self.washHeight)
                    .padding(.leading, Self.labelWidth)
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: Self.laneSpacing) {
                        labelled("SpO₂") {
                            VitalsEnvelopeLane(
                                envelope: envelope, measure: .spo2, laneHeight: Self.spo2LaneHeight
                            )
                        }
                        labelled("PULSE") {
                            VitalsEnvelopeLane(
                                envelope: envelope, measure: .pulse, laneHeight: Self.pulseLaneHeight
                            )
                        }
                    }
                }
                stageLegend
                legend
            }
        }
        .frame(height: Self.totalHeight)
    }

    /// Two legend rows and the gaps around them on top of the lanes themselves.
    static var totalHeight: CGFloat {
        DesaturationRailView.railHeight + spo2LaneHeight + pulseLaneHeight + 84
    }

    private func labelled<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
        }
    }

    /// Names the stage wash behind the lanes.
    ///
    /// Carries the label column like the lanes above it, so it reads as a row of this
    /// chart rather than as a second key for the stage plot. Without it the wash could be
    /// seen but not identified: at wash weight core, deep and REM are close enough that
    /// telling them apart meant counting bands against the plot above.
    ///
    /// Chips are the saturated `themeColor`, matching the stage plot, not the pale wash —
    /// a nine-point swatch at wash opacity is far less legible than the same colour spread
    /// across a whole band, so matching the alpha would not have matched the appearance.
    private var stageLegend: some View {
        let stages = StageBackgroundSpans.legendStages(in: night.displayLaneIntervals)
        return Group {
            if stages.isEmpty {
                EmptyView()
            } else {
                labelled("STAGE") {
                    HStack(spacing: 10) {
                        ForEach(stages, id: \.self) { stage in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(stage.themeColor)
                                    .frame(width: 9, height: 9)
                                Text(stage.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Lane background shows sleep stage: "
                            + stages.map(\.displayName).joined(separator: ", ")
                    )
                }
            }
        }
    }

    /// Numeric labels, never verdicts. The threshold is a display choice; a word like
    /// "Critical" would be an interpretation, which the app does not make.
    /// Labelled like the stage legend above it. Two unlabelled chip rows stacked read as
    /// one wrapped row, and the series blue here is a near match for the core-stage chip
    /// directly above, so the label is what keeps the two keys apart.
    private var legend: some View {
        labelled("SpO₂") {
            HStack(spacing: 12) {
                ForEach(VitalsColorZone.allCases, id: \.self) { zone in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(zone.color)
                            .frame(width: 9, height: 9)
                        Text(zone.legendLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Vitals lanes") {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var spo2 = [UInt8](repeating: 95, count: 3_600)
    for index in 1_200..<1_260 { spo2[index] = 82 }
    for index in 2_400..<2_430 { spo2[index] = 73 }
    let session = VitalsSession(
        id: "preview",
        startDate: start,
        spo2: spo2,
        pulse: (0..<3_600).map { UInt8(55 + ($0 % 20)) },
        motion: [UInt8](repeating: 0, count: 3_600),
        sourceFileNames: ["preview.csv"]
    )
    // Bounds are seconds into a 7,198s recording — the sample interval is 2s, so they are
    // twice the sample indices above. Staged so the preview exercises both questions the
    // wash exists to answer: the 82% dip (samples 1,200–1,260, so 2,400–2,520s) begins
    // exactly on a core→deep transition, and the 73% dip (samples 2,400–2,430, so
    // 4,800–4,860s) sits inside REM.
    let stages: [(TimeInterval, TimeInterval, SleepStage)] = [
        (0, 1_200, .awake),
        (1_200, 2_400, .core),
        (2_400, 3_600, .deep),
        (3_600, 4_700, .core),
        (4_700, 5_400, .rem),
        (5_400, 7_198, .core),
    ]
    let intervals = stages.map { begin, end, stage in
        NormalizedSleepInterval(
            id: "preview-\(stage.rawValue)-\(Int(begin))",
            startDate: start.addingTimeInterval(begin),
            endDate: start.addingTimeInterval(end),
            stage: stage,
            sourceName: "Preview",
            sourceIdentifier: "preview"
        )
    }
    let night = AssembledNight(
        date: start,
        coreWindowStart: start, coreWindowEnd: session.endDate,
        detectedStart: start, detectedEnd: session.endDate,
        rawIntervals: intervals, primaryLaneIntervals: intervals, displayLaneIntervals: intervals,
        conflicts: [], summary: .empty, hasSleepData: true,
        vitalsExtent: session.dateInterval
    )
    return VitalsLanesView(
        session: session,
        events: DesaturationDetector().events(in: session),
        night: night,
        viewportStart: session.startDate,
        viewportEnd: session.endDate
    )
    .padding()
}
