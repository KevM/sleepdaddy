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

struct SleepTimelineCanvasVerticalLayout: Equatable, Sendable {
    let plotHeight: CGFloat
    /// Geometry receives the full canvas height because its vertical calculations subtract
    /// both the top padding and the combined rail; the rendered plot frame excludes the rail.
    let geometryHeight: CGFloat

    init(totalHeight: CGFloat) {
        plotHeight = max(1.0, totalHeight - SleepTimelineGeometry.timeAxisHeight)
        geometryHeight = totalHeight
    }
}

public struct SleepTimelineCanvas: View {
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date
    let selectedIntervalID: String?
    let isInteractive: Bool
    let onSelectInterval: (NormalizedSleepInterval) -> Void
    let onUpdateViewport: (Date, Date) -> Void

    @State private var interaction: TimelineInteractionController
    @State private var gestureResetGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceMotionOverride) private var overrideReduceMotion
    @Environment(\.timelineInteractionEnabled) private var timelineInteractionEnabled
    @Environment(\.calendar) private var calendar

    private var reduceMotion: Bool {
        overrideReduceMotion ?? systemReduceMotion
    }

    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        selectedIntervalID: String?,
        isInteractive: Bool = true,
        onSelectInterval: @escaping (NormalizedSleepInterval) -> Void = { _ in },
        onUpdateViewport: @escaping (Date, Date) -> Void = { _, _ in }
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.selectedIntervalID = selectedIntervalID
        self.isInteractive = isInteractive
        self.onSelectInterval = onSelectInterval
        self.onUpdateViewport = onUpdateViewport

        let initialViewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
        _interaction = State(initialValue: TimelineInteractionController(viewport: initialViewport))
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let totalHeight = proxy.size.height
            let labelWidth: CGFloat = 68.0
            let plotWidth = max(1.0, totalWidth - labelWidth)
            let verticalLayout = SleepTimelineCanvasVerticalLayout(totalHeight: totalHeight)

            let liveViewport = interaction.liveViewport
            let geom = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: liveViewport,
                canvasWidth: plotWidth,
                canvasHeight: verticalLayout.geometryHeight
            )

            let displayedStages = SleepTimelineGeometry.defaultDisplayedStages
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
                .frame(width: labelWidth, height: totalHeight, alignment: .topLeading)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                // Plot region and combined time/context rail
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, canvasSize in
                            let cGeom = SleepTimelineGeometry(
                                totalStart: night.timelineStart,
                                totalEnd: night.timelineEnd,
                                viewport: liveViewport,
                                canvasWidth: canvasSize.width,
                                canvasHeight: verticalLayout.geometryHeight
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
                                let bandY = SleepTimelineGeometry.topPadding
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

                        if isInteractive && timelineInteractionEnabled {
                            // Interactive UIKit overlay
                            TimelineGestureOverlay(
                                resetGeneration: gestureResetGeneration,
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
                                        interaction.updatePan(translationX: translationX, geometry: geom)
                                    }
                                },
                                onPinchChanged: { scale, centroidX in
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        interaction.updateMagnification(scale, anchorX: centroidX, geometry: geom)
                                    }
                                },
                                onInteractionEnded: { velocityX in
                                    let settled = interaction.settledViewport(
                                        geometry: geom,
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
                                    if let tapped = geom.intervalAt(point: location, in: night.displayLaneIntervals, displayedStages: displayedStages) {
                                        onSelectInterval(tapped)
                                    }
                                }
                            )

                            // VoiceOver chronological elements
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
                    .frame(height: verticalLayout.plotHeight)

                    CombinedTimelineRail(
                        night: night,
                        viewport: liveViewport,
                        isInteractive: isInteractive && timelineInteractionEnabled
                    ) { newViewport in
                        onUpdateViewport(newViewport.start, newViewport.end)
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onChange(of: night.id) { _, _ in
            cancelInteraction()
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
