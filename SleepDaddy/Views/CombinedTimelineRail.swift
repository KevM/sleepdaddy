import SwiftUI

struct CombinedTimelineRailInteraction: Equatable, Sendable {
    let startX: CGFloat
    let translationWidth: CGFloat
}

struct CombinedTimelineRailViewportUpdate: Equatable, Sendable {
    let baseline: TimelineViewport
    let viewport: TimelineViewport
}

struct CombinedTimelineRailAccessibilityPresentation: Equatable, Sendable {
    let supportsAdjustment: Bool
    let adjustmentHint: String?

    init(isInteractive: Bool) {
        supportsAdjustment = isInteractive
        adjustmentHint = isInteractive ? "Adjusts the visible time range" : nil
    }
}

struct CombinedTimelineRailLayout: Equatable, Sendable {
    let width: CGFloat

    private var railBounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: SleepTimelineGeometry.timeAxisHeight)
    }

    func interaction(
        startingAt location: CGPoint,
        translationWidth: CGFloat,
        isEnabled: Bool
    ) -> CombinedTimelineRailInteraction? {
        guard isEnabled, railBounds.contains(location) else { return nil }
        return CombinedTimelineRailInteraction(
            startX: min(width, max(0, location.x)),
            translationWidth: translationWidth
        )
    }

    func viewportHandle(fromX startX: CGFloat, toX endX: CGFloat) -> CGRect {
        let handleWidth = min(
            width,
            max(SleepTimelineGeometry.navigatorTrackHeight, endX - startX)
        )
        let centeredOrigin = ((startX + endX) / 2) - (handleWidth / 2)
        let origin = min(max(0, centeredOrigin), max(0, width - handleWidth))
        return CGRect(
            x: origin,
            y: 0,
            width: handleWidth,
            height: SleepTimelineGeometry.navigatorTrackHeight
        )
    }

    func viewportHandle(
        for viewport: TimelineViewport,
        geometry: SleepTimelineGeometry
    ) -> CGRect {
        viewportHandle(
            fromX: geometry.navigatorXRatio(for: viewport.start) * width,
            toX: geometry.navigatorXRatio(for: viewport.end) * width
        )
    }

    func updatedViewport(
        for interaction: CombinedTimelineRailInteraction,
        baseline: TimelineViewport?,
        current: TimelineViewport,
        geometry: SleepTimelineGeometry
    ) -> CombinedTimelineRailViewportUpdate {
        let resolvedBaseline: TimelineViewport
        if let baseline {
            resolvedBaseline = baseline
        } else if viewportHandle(for: current, geometry: geometry).contains(
            CGPoint(x: interaction.startX, y: SleepTimelineGeometry.navigatorTrackHeight / 2)
        ) {
            resolvedBaseline = current
        } else {
            resolvedBaseline = geometry.navigatorViewport(
                current,
                centeredAtX: interaction.startX,
                navigatorWidth: width
            )
        }

        return CombinedTimelineRailViewportUpdate(
            baseline: resolvedBaseline,
            viewport: geometry.navigatorViewport(
                resolvedBaseline,
                translatedBy: interaction.translationWidth,
                navigatorWidth: width
            )
        )
    }
}

struct CombinedTimelineRail: View {
    let night: AssembledNight
    let viewport: TimelineViewport
    let isInteractive: Bool
    let onUpdateViewport: (TimelineViewport) -> Void

    @State private var baselineViewport: TimelineViewport?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    init(
        night: AssembledNight,
        viewport: TimelineViewport,
        isInteractive: Bool = true,
        onUpdateViewport: @escaping (TimelineViewport) -> Void
    ) {
        self.night = night
        self.viewport = viewport
        self.isInteractive = isInteractive
        self.onUpdateViewport = onUpdateViewport
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: viewport,
                canvasWidth: proxy.size.width,
                canvasHeight: proxy.size.height
            )
            let layout = CombinedTimelineRailLayout(width: proxy.size.width)

            VStack(spacing: 0) {
                visibleTimeLabels(geometry: geometry)
                    .frame(height: SleepTimelineGeometry.timeLabelBandHeight)
                    .clipped()
                    .dynamicTypeSize(...DynamicTypeSize.large)

                navigator(geometry: geometry, layout: layout)
                    .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(railGesture(geometry: geometry, layout: layout))
            .allowsHitTesting(isInteractive)
        }
        .frame(height: SleepTimelineGeometry.timeAxisHeight)
        .modifier(
            CombinedTimelineRailAccessibilityModifier(
                label: "Timeline navigator from \(formatted(night.timelineStart)) to \(formatted(night.timelineEnd))",
                presentation: CombinedTimelineRailAccessibilityPresentation(
                    isInteractive: isInteractive
                ),
                onAdjust: adjustViewport
            )
        )
    }

    private func visibleTimeLabels(geometry: SleepTimelineGeometry) -> some View {
        Canvas { context, size in
            let majorTicks = geometry.timeTicks(calendar: calendar)
                .enumerated()
                .filter { $0.element.isMajor }

            var candidates: [TimelineTimeLabelCandidate] = []
            var labels: [Int: GraphicsContext.ResolvedText] = [:]

            for (index, tick) in majorTicks {
                let label = context.resolve(
                    Text(formatted(tick.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                )
                let labelSize = label.measure(in: size)
                candidates.append(
                    TimelineTimeLabelCandidate(
                        index: index,
                        tickX: tick.x,
                        labelWidth: labelSize.width
                    )
                )
                labels[index] = label
            }

            for layout in geometry.timeLabelLayouts(for: candidates) {
                guard let label = labels[layout.candidateIndex] else { continue }
                context.draw(
                    label,
                    at: CGPoint(x: layout.centerX, y: size.height / 2),
                    anchor: .center
                )
            }
        }
    }

    private func navigator(
        geometry: SleepTimelineGeometry,
        layout: CombinedTimelineRailLayout
    ) -> some View {
        let handle = layout.viewportHandle(for: viewport, geometry: geometry)

        return ZStack(alignment: .leading) {
            Color.clear

            Capsule()
                .fill(.quaternary)
                .frame(height: SleepTimelineGeometry.navigatorTrackHeight)

            Capsule()
                .fill(Color.accentColor.opacity(0.35))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                )
                .frame(
                    width: handle.width,
                    height: SleepTimelineGeometry.navigatorTrackHeight
                )
                .offset(x: handle.minX)
        }
    }

    private func railGesture(
        geometry: SleepTimelineGeometry,
        layout: CombinedTimelineRailLayout
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let railInteraction = layout.interaction(
                    startingAt: value.startLocation,
                    translationWidth: value.translation.width,
                    isEnabled: isInteractive
                ) else { return }

                let update = layout.updatedViewport(
                    for: railInteraction,
                    baseline: baselineViewport,
                    current: viewport,
                    geometry: geometry
                )
                baselineViewport = update.baseline
                onUpdateViewport(update.viewport)
            }
            .onEnded { _ in
                baselineViewport = nil
            }
    }

    private func adjustViewport(_ direction: AccessibilityAdjustmentDirection) {
        let sign: Double
        switch direction {
        case .increment: sign = 1
        case .decrement: sign = -1
        @unknown default: return
        }
        onUpdateViewport(
            SleepTimelineGeometry.clamped(
                viewport.shifted(by: viewport.duration * 0.1 * sign),
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd
            )
        )
    }

    private func formatted(_ date: Date) -> String {
        Self.formattedTime(date, locale: locale, timeZone: timeZone)
    }

    static func formattedTime(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
            .locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

private struct CombinedTimelineRailAccessibilityModifier: ViewModifier {
    let label: String
    let presentation: CombinedTimelineRailAccessibilityPresentation
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        let element = content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)

        if presentation.supportsAdjustment, let hint = presentation.adjustmentHint {
            element
                .accessibilityHint(hint)
                .accessibilityAdjustableAction(onAdjust)
        } else {
            element
        }
    }
}
