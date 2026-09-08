import SwiftUI

/// Fixed headings and a generous event hit row; remaining space belongs to the traces.
/// Selection and the key never participate in this budget.
public struct VitalsLanesLayout: Equatable, Sendable {
    public static let defaultHeadingHeight: CGFloat = 24
    public static let laneSpacing: CGFloat = 6
    public static let railHeight: CGFloat = 6
    public static let eventRowHeight: CGFloat = 44
    public static let bottomAir: CGFloat = 8
    public let headingHeight: CGFloat
    public let spo2Height: CGFloat
    public let pulseHeight: CGFloat

    public init(totalHeight: CGFloat, headingHeight: CGFloat = defaultHeadingHeight) {
        self.headingHeight = max(Self.defaultHeadingHeight, headingHeight)
        let free = max(100, totalHeight - Self.fixedHeight(headingHeight: self.headingHeight))
        spo2Height = free * 0.56
        pulseHeight = free * 0.44
    }

    private static func fixedHeight(headingHeight: CGFloat) -> CGFloat {
        max(44, headingHeight) + eventRowHeight + 2 * headingHeight
            + 4 * laneSpacing + bottomAir
    }

    public static func minimumTotalHeight(headingHeight: CGFloat = defaultHeadingHeight) -> CGFloat {
        fixedHeight(headingHeight: max(defaultHeadingHeight, headingHeight)) + 100
    }

    public var headerHeight: CGFloat { max(44, headingHeight) }
    public var washHeight: CGFloat { 2 * headingHeight + 3 * Self.laneSpacing + spo2Height + pulseHeight }
    public var laneRowsHeight: CGFloat { Self.eventRowHeight + Self.laneSpacing + washHeight }
    public var totalHeight: CGFloat { headerHeight + laneRowsHeight + Self.bottomAir }
}

/// Full-width traces with a continuous stage wash and headings above each measure.
public struct VitalsLanesView: View {
    let session: VitalsSession
    let events: [DesaturationEvent]
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date
    let layout: VitalsLanesLayout
    let selectedEvent: DesaturationEvent?
    let showsKeyButton: Bool
    let onShowKey: () -> Void
    let onSelectEvent: (DesaturationEvent) -> Void

    public init(
        session: VitalsSession, events: [DesaturationEvent], night: AssembledNight,
        viewportStart: Date, viewportEnd: Date,
        layout: VitalsLanesLayout = VitalsLanesLayout(totalHeight: VitalsLanesLayout.minimumTotalHeight()),
        selectedEvent: DesaturationEvent? = nil, showsKeyButton: Bool = false,
        onShowKey: @escaping () -> Void = {},
        onSelectEvent: @escaping (DesaturationEvent) -> Void = { _ in }
    ) {
        self.session = session
        self.events = events
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.layout = layout
        self.selectedEvent = selectedEvent
        self.showsKeyButton = showsKeyButton
        self.onShowKey = onShowKey
        self.onSelectEvent = onSelectEvent
    }

    public var body: some View {
        GeometryReader { proxy in
            let viewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
            let geometry = SleepTimelineGeometry(
                totalStart: night.timelineStart, totalEnd: night.timelineEnd,
                viewport: viewport, canvasWidth: proxy.size.width, canvasHeight: proxy.size.height
            )
            let envelope = VitalsEnvelopeBuilder().build(
                session: session, viewport: viewport,
                pixelWidth: max(1, Int((proxy.size.width - 2 * SleepTimelineGeometry.horizontalPlotInset).rounded()))
            )
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Events").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if showsKeyButton {
                        Button(action: onShowKey) {
                            Image(systemName: "info.circle")
                                .font(.body)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Chart key")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: layout.headerHeight)

                DesaturationRailView(events: events, geometry: geometry)
                    .frame(height: VitalsLanesLayout.eventRowHeight)
                    .accessibilityActions {
                        if showsKeyButton {
                            ForEach(events.filter(\.reachesRailThreshold)) { event in
                                Button("Inspect event at \(event.startDate.formatted(date: .omitted, time: .shortened))") {
                                    onSelectEvent(event)
                                }
                            }
                        }
                    }
                ZStack(alignment: .topLeading) {
                    StageBackgroundLane(intervals: night.displayLaneIntervals, geometry: geometry)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: VitalsLanesLayout.laneSpacing) {
                        heading("SpO₂")
                        VitalsEnvelopeLane(envelope: envelope, measure: .spo2, laneHeight: layout.spo2Height)
                            .padding(.horizontal, SleepTimelineGeometry.horizontalPlotInset)
                        heading("Pulse")
                        VitalsEnvelopeLane(envelope: envelope, measure: .pulse, laneHeight: layout.pulseHeight)
                            .padding(.horizontal, SleepTimelineGeometry.horizontalPlotInset)
                    }
                    if let selectedEvent,
                       selectedEvent.endDate >= viewport.start,
                       selectedEvent.startDate <= viewport.end {
                        let x = geometry.xPosition(for: selectedEvent.startDate.addingTimeInterval(selectedEvent.duration / 2))
                        Rectangle()
                            .fill(Color.primary.opacity(0.65))
                            .frame(width: 2)
                            .offset(x: x)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: layout.washHeight)
                .clipped()
                .padding(.top, VitalsLanesLayout.laneSpacing)
            }
        }
        .frame(height: layout.totalHeight)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: layout.headingHeight, alignment: .leading)
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
        viewportEnd: session.endDate,
        layout: VitalsLanesLayout(totalHeight: 320)
    )
    .padding()
}
