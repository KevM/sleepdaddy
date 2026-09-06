import SwiftUI

private struct TimelineInteractionEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    public var timelineInteractionEnabled: Bool {
        get { self[TimelineInteractionEnabledKey.self] }
        set { self[TimelineInteractionEnabledKey.self] = newValue }
    }
}

/// How the card divides its height between the chart it is drawing and the rail.
///
/// Which chart that is depends on the night. With pulse oximetry the vitals *are* the
/// chart and take everything above the rail; without it the stepped stage plot does, laid
/// out exactly as it was before the feature existed. The two are alternatives, never
/// stacked: one night, one picture.
struct SleepTimelineCanvasVerticalLayout: Equatable, Sendable {
    /// The stepped stage plot's frame, excluding the rail. Zero on a night whose chart is
    /// the vitals.
    let plotHeight: CGFloat
    /// The vitals chart's rows, or nil on a night with no pulse oximetry.
    let vitals: VitalsLanesLayout?
    /// Geometry receives the height the chart and its rail occupy together, because its
    /// vertical calculations subtract both the top padding and the rail; the rendered plot
    /// frame excludes the rail.
    let geometryHeight: CGFloat

    init(
        totalHeight: CGFloat,
        hasVitals: Bool = false,
        headingHeight: CGFloat = VitalsLanesLayout.defaultHeadingHeight,
        chrome: TimelineChrome = .interactive
    ) {
        geometryHeight = max(1.0, totalHeight)
        let aboveRail = max(1.0, geometryHeight - chrome.axisHeight)
        if hasVitals {
            vitals = VitalsLanesLayout(
                totalHeight: aboveRail,
                headingHeight: headingHeight
            )
            plotHeight = 0
        } else {
            vitals = nil
            plotHeight = aboveRail
        }
    }

    /// The time-aligned rows the gesture overlay covers as one region, so a pinch works
    /// anywhere a time axis is being drawn, below the chart header.
    var gestureHeight: CGFloat {
        vitals?.laneRowsHeight ?? plotHeight
    }
}

/// The pulse oximetry a night has, when it has any. Its presence is what decides which
/// chart the canvas draws: with a recording the vitals over the stage wash, without one
/// the stepped stage plot.
public struct TimelineVitals {
    let session: VitalsSession
    let events: [DesaturationEvent]

    public init(session: VitalsSession, events: [DesaturationEvent]) {
        self.session = session
        self.events = events
    }
}

public struct SleepTimelineCanvas: View {
    /// The stage plot's own label column, which does not scale: the names in it are
    /// clamped and shrink to fit rather than widening the column.
    static let stageLabelWidth: CGFloat = 68

    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date
    let selectedIntervalID: String?
    let isInteractive: Bool
    let chrome: TimelineChrome
    let vitals: TimelineVitals?
    let onSelectInterval: (NormalizedSleepInterval) -> Void
    let onUpdateViewport: (Date, Date) -> Void

    @State private var interaction: TimelineInteractionController
    @State private var gestureResetGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceMotionOverride) private var overrideReduceMotion
    @Environment(\.timelineInteractionEnabled) private var timelineInteractionEnabled
    @Environment(\.calendar) private var calendar

    @ScaledMetric(relativeTo: .caption) private var scaledHeadingHeight: CGFloat =
        VitalsLanesLayout.defaultHeadingHeight
    @State private var showsVitalsKey = false
    @State private var selectedEventID: Date?

    private var markedEvents: [DesaturationEvent] {
        (vitals?.events ?? []).filter(\.reachesRailThreshold).sorted { $0.startDate < $1.startDate }
    }

    private var reduceMotion: Bool {
        overrideReduceMotion ?? systemReduceMotion
    }

    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        selectedIntervalID: String?,
        isInteractive: Bool = true,
        chrome: TimelineChrome = .interactive,
        vitals: TimelineVitals? = nil,
        onSelectInterval: @escaping (NormalizedSleepInterval) -> Void = { _ in },
        onUpdateViewport: @escaping (Date, Date) -> Void = { _, _ in }
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.selectedIntervalID = selectedIntervalID
        self.isInteractive = isInteractive
        self.chrome = chrome
        self.vitals = vitals
        self.onSelectInterval = onSelectInterval
        self.onUpdateViewport = onUpdateViewport

        let initialViewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
        _interaction = State(initialValue: TimelineInteractionController(viewport: initialViewport))
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let totalHeight = proxy.size.height
            let verticalLayout = SleepTimelineCanvasVerticalLayout(
                totalHeight: totalHeight,
                hasVitals: vitals != nil,
                headingHeight: scaledHeadingHeight,
                chrome: chrome
            )
            // The rail is inset past whichever label column the chart above it reserves.
            let labelWidth: CGFloat = vitals == nil ? Self.stageLabelWidth : 0
            let plotWidth = max(1.0, totalWidth - labelWidth)

            let liveViewport = interaction.liveViewport
            let geom = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: liveViewport,
                canvasWidth: plotWidth,
                canvasHeight: verticalLayout.geometryHeight,
                chrome: chrome
            )

            let displayedStages = SleepTimelineGeometry.defaultDisplayedStages

            let chart = VStack(spacing: 0) {
                if let vitals, let vitalsLayout = verticalLayout.vitals {
                    // The night's chart, not a band under one. Drawn from the canvas's
                    // *live* viewport, so it travels with a gesture instead of snapping
                    // into place when it ends.
                    VitalsLanesView(
                        session: vitals.session,
                        events: vitals.events,
                        night: night,
                        viewportStart: liveViewport.start,
                        viewportEnd: liveViewport.end,
                        layout: vitalsLayout,
                        selectedEvent: markedEvents.first { $0.id == selectedEventID },
                        showsKeyButton: isInteractive && timelineInteractionEnabled,
                        onShowKey: { showsVitalsKey = true },
                        onSelectEvent: { selectEvent($0, geometry: geom) }
                    )
                    .overlay(alignment: .topLeading) {
                        chronologicalIntervals
                    }
                } else {
                    stagePlot(
                        geometry: geom,
                        liveViewport: liveViewport,
                        verticalLayout: verticalLayout,
                        labelWidth: labelWidth,
                        displayedStages: displayedStages
                    )
                }

                // One rail for the whole card, inset to clear the label column that the
                // plot and the lanes both reserve.
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: labelWidth, height: chrome.axisHeight)
                    CombinedTimelineRail(
                        night: night,
                        viewport: liveViewport,
                        isInteractive: isInteractive && timelineInteractionEnabled,
                        chrome: chrome
                    ) { newViewport in
                        onUpdateViewport(newViewport.start, newViewport.end)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                gestureOverlay(
                    geometry: geom,
                    verticalLayout: verticalLayout,
                    plotWidth: plotWidth,
                    labelWidth: labelWidth,
                    displayedStages: displayedStages
                )
            }

            Group {
                if vitals != nil {
                    ScrollView(.vertical) {
                        chart
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    chart
                }
            }
            .overlay(alignment: .bottom) {
                if isInteractive && timelineInteractionEnabled,
                   let index = markedEvents.firstIndex(where: { $0.id == selectedEventID }) {
                    let event = markedEvents[index]
                    let midpoint = event.startDate.addingTimeInterval(event.duration / 2)
                    VitalsEventPanel(
                        event: event, position: index + 1, count: markedEvents.count,
                        stage: night.displayLaneIntervals.first {
                            $0.startDate <= midpoint && midpoint < $0.endDate
                        }?.stage,
                        onPrevious: {
                            guard index > 0 else { return }
                            selectEvent(markedEvents[index - 1], geometry: geom)
                        },
                        onNext: {
                            guard index + 1 < markedEvents.count else { return }
                            selectEvent(markedEvents[index + 1], geometry: geom)
                        },
                        onDismiss: { selectedEventID = nil }
                    )
                    .frame(height: min(totalHeight, max(240, totalHeight * 0.60)))
                    .padding(8)
                }
            }
        }
        .sheet(isPresented: $showsVitalsKey) {
            VitalsChartKeyView()
        }
        .modifier(TimelineSurface(isVisible: chrome.showsCardSurface))
        .onChange(of: night.id) { _, _ in
            selectedEventID = nil
            showsVitalsKey = false
            cancelInteraction()
        }
        .onChange(of: vitals?.session.id) { _, _ in
            selectedEventID = nil
        }
        .onChange(of: vitals?.events) { _, _ in
            if !markedEvents.contains(where: { $0.id == selectedEventID }) {
                selectedEventID = nil
            }
        }
        .onChange(of: viewportStart) { _, _ in
            cancelInteraction()
        }
        .onChange(of: viewportEnd) { _, _ in
            cancelInteraction()
        }
        .onDisappear {
            cancelInteraction()
        }
    }

    /// The stepped stage plot and its fixed leading label column: the chart a night
    /// without pulse oximetry is read from, unchanged by the vitals feature existing.
    @ViewBuilder
    private func stagePlot(
        geometry geom: SleepTimelineGeometry,
        liveViewport: TimelineViewport,
        verticalLayout: SleepTimelineCanvasVerticalLayout,
        labelWidth: CGFloat,
        displayedStages: [SleepStage]
    ) -> some View {
        let stagePercentages = night.summary.stagePercentages
        HStack(alignment: .top, spacing: 0) {
            // Fixed leading stage labels outside moving plot region
            ZStack(alignment: .topLeading) {
                ForEach(displayedStages, id: \.self) { stage in
                    let yCenter = geom.yCenterPosition(for: stage, displayedStages: displayedStages)
                    let percentage = stagePercentages[stage]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.displayName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(stage.themeColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let percentage {
                            Text("\(percentage)%")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(width: labelWidth, alignment: .leading)
                    .position(x: labelWidth / 2.0, y: yCenter)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        percentage.map { "\(stage.displayName), \($0) percent of night" }
                            ?? stage.displayName
                    )
                }
            }
            .frame(width: labelWidth, height: verticalLayout.plotHeight, alignment: .topLeading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            ZStack(alignment: .topLeading) {
                Canvas { context, canvasSize in
                    let cGeom = SleepTimelineGeometry(
                        totalStart: night.timelineStart,
                        totalEnd: night.timelineEnd,
                        viewport: liveViewport,
                        canvasWidth: canvasSize.width,
                        canvasHeight: verticalLayout.geometryHeight,
                        chrome: chrome
                    )

                    // 1. Guideline rows
                    for stage in displayedStages {
                        let y = cGeom.yCenterPosition(for: stage, displayedStages: displayedStages)
                        var linePath = Path()
                        linePath.move(to: CGPoint(x: 0, y: y))
                        linePath.addLine(to: CGPoint(x: canvasSize.width, y: y))
                        context.stroke(linePath, with: .color(Color.gray.opacity(0.12)), lineWidth: 1)
                    }

                    // 2. In Bed background band
                    let inBedIntervals = night.rawIntervals.filter { $0.stage == .inBed }
                    if !inBedIntervals.isEmpty {
                        let bandY = chrome.topPadding
                        let lastStage = displayedStages.last ?? .deep
                        let lastYCenter = cGeom.yCenterPosition(for: lastStage, displayedStages: displayedStages)
                        let rHeight = cGeom.rowHeight(displayedStagesCount: displayedStages.count)
                        let bandHeight = max(1.0, (lastYCenter + rHeight / 2.0) - bandY + 4)

                        for inBed in inBedIntervals {
                            let x1 = cGeom.xPosition(for: inBed.startDate)
                            let x2 = cGeom.xPosition(for: inBed.endDate)
                            let width = max(2.0, x2 - x1)
                            let bandRect = CGRect(x: x1, y: bandY, width: width, height: bandHeight)
                            let path = Path(roundedRect: bandRect, cornerRadius: 4)
                            context.fill(path, with: .color(SleepStage.inBed.themeColor.opacity(0.12)))
                        }
                    }

                    // 3. Conflict ranges & markers
                    for conflict in night.conflicts {
                        let x1 = cGeom.xPosition(for: conflict.startDate)
                        let x2 = cGeom.xPosition(for: conflict.endDate)
                        let width = max(4.0, x2 - x1)
                        let conflictRect = CGRect(x: x1, y: 0, width: width, height: canvasSize.height)

                        let path = Path(roundedRect: conflictRect, cornerRadius: 2)
                        context.fill(path, with: .color(Color.yellow.opacity(0.20)))
                        context.stroke(path, with: .color(Color.orange.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        let markerPoint = CGPoint(x: x1 + width / 2.0, y: 6)
                        let circlePath = Path(ellipseIn: CGRect(x: markerPoint.x - 3, y: markerPoint.y - 3, width: 6, height: 6))
                        context.fill(circlePath, with: .color(Color.orange))
                    }

                    // 4. Unspecified sleep spanning bands
                    for interval in night.displayLaneIntervals where interval.stage == .asleepUnspecified {
                        let bandRect = cGeom.rect(for: interval, displayedStages: displayedStages)
                        let path = Path(roundedRect: bandRect, cornerRadius: 6)
                        context.fill(path, with: .color(interval.stage.themeColor))
                    }

                    // 5. Stepped sleep path
                    let stepSegments = cGeom.stepSegments(for: night.displayLaneIntervals, displayedStages: displayedStages)
                    for segment in stepSegments
                    where segment.isConnector || segment.stage != .asleepUnspecified {
                        var segmentPath = Path()
                        segmentPath.move(to: segment.start)
                        segmentPath.addLine(to: segment.end)

                        if segment.isConnector {
                            context.stroke(
                                segmentPath,
                                with: .color(segment.stage.themeColor.opacity(0.55)),
                                style: StrokeStyle(lineWidth: 2, lineCap: .butt)
                            )
                        } else {
                            context.stroke(
                                segmentPath,
                                with: .color(segment.stage.themeColor),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                        }
                    }

                    // 6. Selected segment emphasis
                    if let selectedID = selectedIntervalID,
                        let selectedInterval = night.displayLaneIntervals.first(where: { $0.id == selectedID })
                    {
                        if selectedInterval.stage == .asleepUnspecified {
                            let selectedRect = cGeom.rect(
                                for: selectedInterval,
                                displayedStages: displayedStages
                            )
                            let selectedPath = Path(roundedRect: selectedRect, cornerRadius: 6)
                            context.stroke(
                                selectedPath,
                                with: .color(Color.white),
                                lineWidth: 3
                            )
                        } else {
                            let startX = cGeom.xPosition(for: selectedInterval.startDate)
                            let endX = cGeom.xPosition(for: selectedInterval.endDate)
                            let y = cGeom.yCenterPosition(for: selectedInterval.stage, displayedStages: displayedStages)

                            var selPath = Path()
                            selPath.move(to: CGPoint(x: startX, y: y))
                            selPath.addLine(to: CGPoint(x: endX, y: y))

                            context.stroke(
                                selPath,
                                with: .color(Color.white),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            context.stroke(
                                selPath,
                                with: .color(selectedInterval.stage.themeColor),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                        }
                    }

                    // 7. Time tick guidelines
                    let ticks = cGeom.timeTicks(calendar: calendar)

                    for tick in ticks {
                        var tickPath = Path()
                        tickPath.move(to: CGPoint(x: tick.x, y: 0))
                        tickPath.addLine(to: CGPoint(x: tick.x, y: canvasSize.height))
                        let opacity = tick.isMajor ? 0.2 : 0.08
                        context.stroke(tickPath, with: .color(Color.gray.opacity(opacity)), lineWidth: 1)
                    }
                }

                chronologicalIntervals
            }
            .frame(height: verticalLayout.plotHeight)
        }
    }

    /// The night's intervals in time order, as zero-size elements VoiceOver can step
    /// through. It is the whole chart to a VoiceOver reader — the drawn wash and
    /// stepped path are all hidden from it — so it belongs to whichever chart is on
    /// screen, not to the stage plot in particular.
    @ViewBuilder
    private var chronologicalIntervals: some View {
        if isInteractive && timelineInteractionEnabled {
            VStack(spacing: 0) {
                ForEach(night.displayLaneIntervals) { interval in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(interval.accessibilityDescription)
                        .accessibilityHint("Double tap to inspect interval details and options")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            onSelectInterval(interval)
                        }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sleep Timeline Chronological Intervals")
        }
    }

    /// Pan, pinch and tap for whichever chart the night is showing, covering every
    /// time-aligned row as one region.
    ///
    /// Lives outside the chart so a drag that starts on an SpO₂ dip and travels up into
    /// the events rail stays a single gesture. It is inset past the label column rather
    /// than covering it, which leaves the row labels reachable by VoiceOver.
    @ViewBuilder
    private func gestureOverlay(
        geometry: SleepTimelineGeometry,
        verticalLayout: SleepTimelineCanvasVerticalLayout,
        plotWidth: CGFloat,
        labelWidth: CGFloat,
        displayedStages: [SleepStage]
    ) -> some View {
        if isInteractive && timelineInteractionEnabled {
            TimelineGestureOverlay(
                resetGeneration: gestureResetGeneration,
                allowsVerticalScrolling: verticalLayout.vitals != nil,
                onInteractionBegan: {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        interaction.begin(viewport: TimelineViewport(normalizing: viewportStart, end: viewportEnd))
                    }
                },
                onPanChanged: { translationX in
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        interaction.updatePan(translationX: translationX, geometry: geometry)
                    }
                },
                onPinchChanged: { scale, centroidX in
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        interaction.updateMagnification(scale, anchorX: centroidX, geometry: geometry)
                    }
                },
                onInteractionEnded: { velocityX in
                    let settled = interaction.settledViewport(
                        geometry: geometry,
                        velocityX: velocityX,
                        reduceMotion: reduceMotion
                    )
                    if reduceMotion {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onUpdateViewport(settled.start, settled.end)
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            onUpdateViewport(settled.start, settled.end)
                        }
                    }
                },
                onInteractionCancelled: {
                    cancelInteraction(invalidateRecognizers: false)
                },
                onTap: { location in
                    if verticalLayout.vitals != nil,
                       location.y <= VitalsLanesLayout.eventRowHeight {
                        if let event = geometry.event(atX: location.x, in: markedEvents) {
                            selectEvent(event, geometry: geometry)
                        }
                        return
                    }
                    guard let tapped = tappedInterval(
                        at: location,
                        geometry: geometry,
                        verticalLayout: verticalLayout,
                        displayedStages: displayedStages
                    ) else { return }
                    onSelectInterval(tapped)
                }
            )
            .frame(width: plotWidth, height: verticalLayout.gestureHeight)
            .padding(.leading, labelWidth)
            .padding(.top, verticalLayout.vitals?.headerHeight ?? 0)
        }
    }

    private func selectEvent(_ event: DesaturationEvent, geometry: SleepTimelineGeometry) {
        selectedEventID = event.id
        let viewport = geometry.viewport(centeredAt: event.startDate.addingTimeInterval(event.duration / 2))
        onUpdateViewport(viewport.start, viewport.end)
    }

    /// The interval a tap landed on, or `nil` where it hit empty chart.
    ///
    /// The two charts are hit-tested differently because they are drawn differently: the
    /// stepped plot gives each stage its own row, so a tap between rows means nothing and
    /// y has to be honoured. The vitals chart stacks every stage into rows that share one
    /// axis, so y carries no information and time alone picks the interval.
    private func tappedInterval(
        at location: CGPoint,
        geometry: SleepTimelineGeometry,
        verticalLayout: SleepTimelineCanvasVerticalLayout,
        displayedStages: [SleepStage]
    ) -> NormalizedSleepInterval? {
        if verticalLayout.vitals != nil {
            return geometry.interval(atX: location.x, in: night.displayLaneIntervals)
        }
        return geometry.intervalAt(
            point: location,
            in: night.displayLaneIntervals,
            displayedStages: displayedStages
        )
    }

    private func cancelInteraction(invalidateRecognizers: Bool = true) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            interaction.cancel(
                viewport: TimelineViewport(normalizing: viewportStart, end: viewportEnd)
            )
            if invalidateRecognizers {
                gestureResetGeneration &+= 1
            }
        }
    }
}

/// The rounded, shadowed surface the timeline draws itself on when it is a card on screen.
///
/// Suppressed for export, where `ShareTimelineCardView` supplies the only surface — nesting
/// the two produces a visible card-inside-a-card.
private struct TimelineSurface: ViewModifier {
    let isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        } else {
            content
        }
    }
}
