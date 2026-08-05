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

            VStack(alignment: .leading, spacing: 6) {
                labelled("EVENTS") {
                    DesaturationRailView(events: events, geometry: geometry)
                }
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
                legend
            }
        }
        .frame(height: Self.totalHeight)
    }

    static var totalHeight: CGFloat {
        DesaturationRailView.railHeight + spo2LaneHeight + pulseLaneHeight + 60
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

    /// Numeric labels, never verdicts. The threshold is a display choice; a word like
    /// "Critical" would be an interpretation, which the app does not make.
    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(VitalsColorZone.allCases, id: \.self) { zone in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.color)
                        .frame(width: 9, height: 9)
                    Text(zone.legendLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, Self.labelWidth)
        .accessibilityElement(children: .combine)
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
    let night = AssembledNight(
        date: start,
        coreWindowStart: start, coreWindowEnd: session.endDate,
        detectedStart: start, detectedEnd: session.endDate,
        rawIntervals: [], primaryLaneIntervals: [], displayLaneIntervals: [],
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
