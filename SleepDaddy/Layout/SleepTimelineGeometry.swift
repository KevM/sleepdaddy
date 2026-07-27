import Foundation
import CoreGraphics

public struct SleepTimelineGeometry: Sendable {
    public let totalStart: Date
    public let totalEnd: Date
    public let viewport: TimelineViewport
    public let canvasWidth: CGFloat
    public let canvasHeight: CGFloat

    public static let rowHeight: CGFloat = 36.0
    public static let rowSpacing: CGFloat = 8.0
    public static let topPadding: CGFloat = 16.0
    /// Keeps the widest selected timeline stroke (14 points) inside the clipped canvas.
    public static let horizontalPlotInset: CGFloat = 7.0

    /// Shortest window the timeline may be zoomed into, in seconds.
    public static let minimumViewportDuration: TimeInterval = 300.0

    public var totalDuration: TimeInterval {
        max(1.0, totalEnd.timeIntervalSince(totalStart))
    }

    public var viewportDuration: TimeInterval {
        viewport.duration
    }

    private var plotWidth: CGFloat {
        max(0, canvasWidth - 2 * Self.horizontalPlotInset)
    }

    public init(
        totalStart: Date,
        totalEnd: Date,
        viewport: TimelineViewport,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) {
        self.totalStart = totalStart
        self.totalEnd = totalEnd
        self.viewport = viewport
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    /// Returns a copy of this geometry showing a different window of the same night.
    public func replacingViewport(_ viewport: TimelineViewport) -> Self {
        Self(
            totalStart: totalStart,
            totalEnd: totalEnd,
            viewport: viewport,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
    }

    /// Converts a Date to an X position in canvas coordinates
    public func xPosition(for date: Date) -> CGFloat {
        guard viewportDuration > 0, plotWidth > 0 else { return 0 }
        let progress = date.timeIntervalSince(viewport.start) / viewportDuration
        return Self.horizontalPlotInset + CGFloat(progress) * plotWidth
    }

    /// Converts an X position in canvas coordinates to a Date
    public func date(atX x: CGFloat) -> Date {
        guard plotWidth > 0 else { return viewport.start }
        let plotX = min(plotWidth, max(0, x - Self.horizontalPlotInset))
        let progress = Double(plotX / plotWidth)
        return viewport.start.addingTimeInterval(progress * viewportDuration)
    }

    /// Places measured time labels without clipping or overlap.
    ///
    /// The first and last feasible labels are reserved so edge clamping cannot let a nearby
    /// interior label cover them. Remaining labels stay centered on their ticks whenever they
    /// fit and are culled when their bounds would intersect a retained label.
    func timeLabelLayouts(
        for candidates: [TimelineTimeLabelCandidate]
    ) -> [TimelineTimeLabelLayout] {
        guard canvasWidth.isFinite, canvasWidth > 0 else { return [] }

        let positioned = candidates.compactMap { candidate -> TimelineTimeLabelLayout? in
            guard candidate.tickX.isFinite, candidate.labelWidth.isFinite else { return nil }
            let width = max(0, candidate.labelWidth)
            guard width <= canvasWidth else { return nil }

            let halfWidth = width / 2
            let centerX = min(canvasWidth - halfWidth, max(halfWidth, candidate.tickX))
            return TimelineTimeLabelLayout(
                candidateIndex: candidate.index,
                centerX: centerX,
                labelWidth: width
            )
        }
        guard let first = positioned.first else { return [] }

        var retained = [first]
        if let last = positioned.last,
           last.candidateIndex != first.candidateIndex,
           !last.overlaps(anyOf: retained) {
            retained.append(last)
        }

        if positioned.count > 2 {
            for candidate in positioned.dropFirst().dropLast()
            where !candidate.overlaps(anyOf: retained) {
                retained.append(candidate)
            }
        }

        return retained.sorted {
            if $0.centerX == $1.centerX {
                return $0.candidateIndex < $1.candidateIndex
            }
            return $0.centerX < $1.centerX
        }
    }

    public static let timeAxisHeight: CGFloat = 28.0
    public static let defaultDisplayedStages: [SleepStage] = [.awake, .rem, .core, .deep]

    public func usablePlotHeight() -> CGFloat {
        max(120.0, canvasHeight - Self.topPadding - Self.timeAxisHeight)
    }

    public func laneHeight(displayedStagesCount count: Int) -> CGFloat {
        usablePlotHeight() / max(1.0, CGFloat(count))
    }

    public func yCenterPosition(
        for stage: SleepStage,
        displayedStages: [SleepStage] = defaultDisplayedStages
    ) -> CGFloat {
        if stage == .asleepUnspecified,
           displayedStages.contains(.rem),
           displayedStages.contains(.deep) {
            let remCenter = yCenterPosition(for: .rem, displayedStages: displayedStages)
            let deepCenter = yCenterPosition(for: .deep, displayedStages: displayedStages)
            return (remCenter + deepCenter) / 2.0
        }

        guard let index = displayedStages.firstIndex(of: stage) else {
            return Self.topPadding
        }
        let lHeight = laneHeight(displayedStagesCount: displayedStages.count)
        return Self.topPadding + (CGFloat(index) + 0.5) * lHeight
    }

    public func rowHeight(displayedStagesCount count: Int = defaultDisplayedStages.count) -> CGFloat {
        let lHeight = laneHeight(displayedStagesCount: count)
        return min(36.0, max(16.0, lHeight * 0.65))
    }

    /// Y coordinate for a given SleepStage row
    public func yPosition(
        for stage: SleepStage,
        displayedStages: [SleepStage] = defaultDisplayedStages
    ) -> CGFloat {
        let yCenter = yCenterPosition(for: stage, displayedStages: displayedStages)
        let rHeight = rowHeight(displayedStagesCount: displayedStages.count)
        return yCenter - rHeight / 2.0
    }

    /// Computes the bounding CGRect for an interval
    public func rect(
        for interval: NormalizedSleepInterval,
        displayedStages: [SleepStage] = defaultDisplayedStages
    ) -> CGRect {
        let x1 = xPosition(for: interval.startDate)
        let x2 = xPosition(for: interval.endDate)
        let width = max(2.0, x2 - x1)
        let rHeight = rowHeight(displayedStagesCount: displayedStages.count)

        if interval.stage == .asleepUnspecified,
           displayedStages.contains(.rem),
           displayedStages.contains(.deep) {
            let minY = yPosition(for: .rem, displayedStages: displayedStages)
            let maxY = yPosition(for: .deep, displayedStages: displayedStages) + rHeight
            return CGRect(x: x1, y: minY, width: width, height: maxY - minY)
        }

        let y = yPosition(for: interval.stage, displayedStages: displayedStages)
        return CGRect(x: x1, y: y, width: width, height: rHeight)
    }

    /// Calculates the viewport after a pinch zoom relative to an anchor point in X.
    ///
    /// A magnification greater than 1 zooms in. The date sitting under `anchorX` in
    /// `baseline` stays under `anchorX` in the result, so the pinch feels focal.
    public func zoomed(
        _ baseline: TimelineViewport,
        magnification: CGFloat,
        anchorX: CGFloat
    ) -> TimelineViewport {
        let ratio = anchorRatio(atX: anchorX)
        let anchorDate = baseline.start.addingTimeInterval(ratio * baseline.duration)

        let scale = max(0.0001, Double(magnification))
        let targetDuration = baseline.duration / scale

        let proposedStart = anchorDate.addingTimeInterval(-ratio * targetDuration)
        let proposed = TimelineViewport(
            start: proposedStart,
            end: proposedStart.addingTimeInterval(targetDuration)
        )
        return clamped(proposed, anchorDate: anchorDate)
    }

    /// Calculates the viewport after a drag pan, preserving its duration.
    ///
    /// Dragging content to the left (a negative `deltaX`) moves the viewport later in time.
    public func panned(_ baseline: TimelineViewport, deltaX: CGFloat) -> TimelineViewport {
        clamped(unclampedPanned(baseline, deltaX: deltaX))
    }

    /// The pan `panned(_:deltaX:)` proposes before the night's bounds are applied.
    ///
    /// Exposed so callers that want to render overscroll can measure exactly how much
    /// of a drag clamping rejected. Comparing this against `panned` is reliable only
    /// because both run the identical translation; deriving the shift a second time
    /// elsewhere would leave the two to drift apart.
    public func unclampedPanned(_ baseline: TimelineViewport, deltaX: CGFloat) -> TimelineViewport {
        let timeShift = -Double(deltaX / max(1.0, plotWidth)) * baseline.duration
        return baseline.shifted(by: timeShift)
    }

    /// Clamps a proposed viewport into the night.
    ///
    /// The duration is limited to `minimumViewportDuration ... totalDuration`. When it has
    /// to change, `anchorDate` (defaulting to the proposed midpoint) keeps its relative
    /// position inside the window; the result is then translated to fit within
    /// `[totalStart, totalEnd]`.
    public func clamped(_ proposed: TimelineViewport, anchorDate: Date? = nil) -> TimelineViewport {
        let maxDuration = totalDuration
        let minDuration = min(Self.minimumViewportDuration, maxDuration)
        let targetDuration = min(maxDuration, max(minDuration, proposed.duration))

        var start: Date
        if targetDuration == proposed.duration {
            start = proposed.start
        } else {
            let anchor = anchorDate ?? proposed.midpoint
            let rawRatio = anchor.timeIntervalSince(proposed.start) / proposed.duration
            let ratio = min(1.0, max(0.0, rawRatio))
            start = anchor.addingTimeInterval(-ratio * targetDuration)
        }

        if start.addingTimeInterval(targetDuration) > totalEnd {
            start = totalEnd.addingTimeInterval(-targetDuration)
        }
        if start < totalStart {
            start = totalStart
        }

        return TimelineViewport(start: start, end: start.addingTimeInterval(targetDuration))
    }

    /// Normalized horizontal position (0.0 ... 1.0) of an X coordinate on the canvas
    private func anchorRatio(atX x: CGFloat) -> Double {
        let ratio = Double((x - Self.horizontalPlotInset) / max(1.0, plotWidth))
        return min(1.0, max(0.0, ratio))
    }

    /// Hit test to find which interval is tapped
    public func intervalAt(
        point: CGPoint,
        in intervals: [NormalizedSleepInterval],
        displayedStages: [SleepStage] = defaultDisplayedStages
    ) -> NormalizedSleepInterval? {
        for interval in intervals {
            let r = rect(for: interval, displayedStages: displayedStages)
            if r.contains(point) {
                return interval
            }
        }
        return nil
    }

    /// Returns normalized x ratio (0.0 ... 1.0) for context navigator
    public func navigatorXRatio(for date: Date) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        let progress = date.timeIntervalSince(totalStart) / totalDuration
        return CGFloat(min(1.0, max(0.0, progress)))
    }

    /// Calculates the viewport after translating the overview navigator window by `deltaX` points across `navigatorWidth`.
    public func navigatorViewport(
        _ baseline: TimelineViewport,
        translatedBy deltaX: CGFloat,
        navigatorWidth: CGFloat
    ) -> TimelineViewport {
        let ratio = Double(deltaX / max(1.0, navigatorWidth))
        let timeShift = ratio * totalDuration
        let proposed = baseline.shifted(by: timeShift)
        return clamped(proposed)
    }

    /// Calculates the viewport after recentering the overview navigator window at point `x` across `navigatorWidth`.
    public func navigatorViewport(
        _ baseline: TimelineViewport,
        centeredAtX x: CGFloat,
        navigatorWidth: CGFloat
    ) -> TimelineViewport {
        let ratio = min(1.0, max(0.0, Double(x / max(1.0, navigatorWidth))))
        let centerDate = totalStart.addingTimeInterval(ratio * totalDuration)
        let halfDuration = baseline.duration / 2.0
        let proposed = TimelineViewport(
            start: centerDate.addingTimeInterval(-halfDuration),
            end: centerDate.addingTimeInterval(halfDuration)
        )
        return clamped(proposed)
    }


    /// Generates stepped-path segments (horizontal centerlines and vertical connectors) for the given intervals.
    public func stepSegments(
        for intervals: [NormalizedSleepInterval],
        displayedStages: [SleepStage] = defaultDisplayedStages
    ) -> [TimelineStepSegment] {
        let primaryIntervals = intervals
            .filter { $0.stage != .inBed }
            .sorted { $0.startDate < $1.startDate }

        guard !primaryIntervals.isEmpty else { return [] }

        var segments: [TimelineStepSegment] = []

        for i in 0..<primaryIntervals.count {
            let current = primaryIntervals[i]
            let startX = xPosition(for: current.startDate)
            let endX = xPosition(for: current.endDate)
            let currentY = yCenterPosition(for: current.stage, displayedStages: displayedStages)

            if i > 0 {
                let prev = primaryIntervals[i - 1]
                let prevY = yCenterPosition(for: prev.stage, displayedStages: displayedStages)
                let touchesInTime = abs(current.startDate.timeIntervalSince(prev.endDate)) < 0.001

                if touchesInTime && prev.stage != current.stage {
                    let connector = TimelineStepSegment(
                        start: CGPoint(x: startX, y: prevY),
                        end: CGPoint(x: startX, y: currentY),
                        stage: current.stage,
                        isConnector: true
                    )
                    segments.append(connector)
                }
            }

            let horizontalSegment = TimelineStepSegment(
                start: CGPoint(x: startX, y: currentY),
                end: CGPoint(x: endX, y: currentY),
                stage: current.stage,
                isConnector: false
            )
            segments.append(horizontalSegment)
        }

        return segments
    }

    /// Generates adaptive time ticks across the visible viewport window.
    public func timeTicks(calendar: Calendar = .current) -> [TimelineTimeTick] {
        guard canvasWidth > 0, viewportDuration > 0 else { return [] }

        let steps: [TimeInterval] = [300, 900, 1_800, 3_600, 7_200]
        let idealStep = (80.0 / canvasWidth) * viewportDuration

        let stepInSeconds = steps.min(by: { abs($0 - idealStep) < abs($1 - idealStep) }) ?? 3600.0

        let startInterval = viewport.start.timeIntervalSince1970
        let firstTickInterval = floor(startInterval / stepInSeconds) * stepInSeconds
        var current = Date(timeIntervalSince1970: firstTickInterval)

        var ticks: [TimelineTimeTick] = []
        let endBoundary = viewport.end.addingTimeInterval(0.001)

        while current <= endBoundary {
            if current >= viewport.start.addingTimeInterval(-0.001) {
                let x = xPosition(for: current)
                let minute = calendar.component(.minute, from: current)
                let isMajor: Bool
                if stepInSeconds >= 3600 {
                    isMajor = minute == 0
                } else if stepInSeconds >= 1800 {
                    isMajor = minute == 0
                } else {
                    isMajor = minute % 15 == 0
                }
                ticks.append(TimelineTimeTick(date: current, x: x, isMajor: isMajor))
            }
            current = current.addingTimeInterval(stepInSeconds)
        }

        return ticks
    }
}

public struct TimelineStepSegment: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint
    public let stage: SleepStage
    public let isConnector: Bool

    public init(start: CGPoint, end: CGPoint, stage: SleepStage, isConnector: Bool) {
        self.start = start
        self.end = end
        self.stage = stage
        self.isConnector = isConnector
    }
}

public struct TimelineTimeTick: Equatable, Sendable {
    public let date: Date
    public let x: CGFloat
    public let isMajor: Bool

    public init(date: Date, x: CGFloat, isMajor: Bool) {
        self.date = date
        self.x = x
        self.isMajor = isMajor
    }
}

struct TimelineTimeLabelCandidate: Equatable, Sendable {
    let index: Int
    let tickX: CGFloat
    let labelWidth: CGFloat
}

struct TimelineTimeLabelLayout: Equatable, Sendable {
    let candidateIndex: Int
    let centerX: CGFloat
    let labelWidth: CGFloat

    private var minX: CGFloat { centerX - labelWidth / 2 }
    private var maxX: CGFloat { centerX + labelWidth / 2 }

    fileprivate func overlaps(anyOf layouts: [Self]) -> Bool {
        layouts.contains { minX < $0.maxX && $0.minX < maxX }
    }
}
