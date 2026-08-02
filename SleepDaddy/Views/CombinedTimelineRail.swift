import SwiftUI

struct CombinedTimelineRailInteraction: Equatable, Sendable {
    let startX: CGFloat
    let translationWidth: CGFloat
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
}

struct CombinedTimelineRailLabelDynamicTypeSizePreferenceKey: PreferenceKey {
    static let defaultValue: DynamicTypeSize? = nil

    static func reduce(value: inout DynamicTypeSize?, nextValue: () -> DynamicTypeSize?) {
        value = nextValue() ?? value
    }
}

private struct CombinedTimelineRailLabelDynamicTypeSizeReporter: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Color.clear.preference(
            key: CombinedTimelineRailLabelDynamicTypeSizePreferenceKey.self,
            value: dynamicTypeSize
        )
    }
}

struct CombinedTimelineRailLabelBandBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct CombinedTimelineRailNavigatorBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
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
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .anchorPreference(
                        key: CombinedTimelineRailLabelBandBoundsPreferenceKey.self,
                        value: .bounds
                    ) { $0 }

                navigator(geometry: geometry, layout: layout)
                    .frame(maxHeight: .infinity)
                    .anchorPreference(
                        key: CombinedTimelineRailNavigatorBoundsPreferenceKey.self,
                        value: .bounds
                    ) { $0 }
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
        .overlay {
            CombinedTimelineRailLabelDynamicTypeSizeReporter()
        }
    }

    private func navigator(
        geometry: SleepTimelineGeometry,
        layout: CombinedTimelineRailLayout
    ) -> some View {
        let viewportX1 = geometry.navigatorXRatio(for: viewport.start) * layout.width
        let viewportX2 = geometry.navigatorXRatio(for: viewport.end) * layout.width
        let handle = layout.viewportHandle(fromX: viewportX1, toX: viewportX2)

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

                let viewportX1 = geometry.navigatorXRatio(for: viewport.start) * layout.width
                let viewportX2 = geometry.navigatorXRatio(for: viewport.end) * layout.width
                let handle = layout.viewportHandle(fromX: viewportX1, toX: viewportX2)
                let baseline: TimelineViewport
                if let baselineViewport {
                    baseline = baselineViewport
                } else if handle.contains(
                    CGPoint(x: railInteraction.startX, y: handle.midY)
                ) {
                    baseline = viewport
                    baselineViewport = viewport
                } else {
                    baseline = geometry.navigatorViewport(
                        viewport,
                        centeredAtX: railInteraction.startX,
                        navigatorWidth: layout.width
                    )
                    onUpdateViewport(baseline)
                    baselineViewport = baseline
                }

                onUpdateViewport(
                    geometry.navigatorViewport(
                        baseline,
                        translatedBy: railInteraction.translationWidth,
                        navigatorWidth: layout.width
                    )
                )
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
        let geometry = SleepTimelineGeometry(
            totalStart: night.timelineStart,
            totalEnd: night.timelineEnd,
            viewport: viewport,
            canvasWidth: 1,
            canvasHeight: SleepTimelineGeometry.timeAxisHeight
        )
        onUpdateViewport(
            geometry.clamped(viewport.shifted(by: viewport.duration * 0.1 * sign))
        )
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
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
