import SwiftUI

struct CombinedTimelineRail: View {
    let night: AssembledNight
    let viewport: TimelineViewport
    let onUpdateViewport: (TimelineViewport) -> Void

    @State private var baselineViewport: TimelineViewport?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        GeometryReader { proxy in
            let geometry = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: viewport,
                canvasWidth: proxy.size.width,
                canvasHeight: proxy.size.height
            )

            VStack(spacing: 0) {
                visibleTimeLabels(geometry: geometry)
                    .frame(height: SleepTimelineGeometry.timeLabelBandHeight)

                navigator(geometry: geometry, width: proxy.size.width)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(height: SleepTimelineGeometry.timeAxisHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Timeline navigator from \(formatted(night.timelineStart)) to \(formatted(night.timelineEnd))"
        )
        .accessibilityHint("Adjusts the visible time range")
        .accessibilityAdjustableAction { direction in
            adjustViewport(direction)
        }
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

    private func navigator(geometry: SleepTimelineGeometry, width: CGFloat) -> some View {
        let viewportX1 = geometry.navigatorXRatio(for: viewport.start) * width
        let viewportX2 = geometry.navigatorXRatio(for: viewport.end) * width
        let viewportWidth = max(
            SleepTimelineGeometry.navigatorTrackHeight,
            viewportX2 - viewportX1
        )

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
                    width: viewportWidth,
                    height: SleepTimelineGeometry.navigatorTrackHeight
                )
                .offset(x: viewportX1)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let baseline: TimelineViewport
                    if let baselineViewport {
                        baseline = baselineViewport
                    } else {
                        let touchX = value.startLocation.x
                        let isInsideHandle = touchX >= viewportX1 && touchX <= (viewportX1 + viewportWidth)
                        if isInsideHandle {
                            baseline = viewport
                        } else {
                            baseline = geometry.navigatorViewport(
                                viewport,
                                centeredAtX: touchX,
                                navigatorWidth: width
                            )
                            onUpdateViewport(baseline)
                        }
                        baselineViewport = baseline
                    }

                    onUpdateViewport(
                        geometry.navigatorViewport(
                            baseline,
                            translatedBy: value.translation.width,
                            navigatorWidth: width
                        )
                    )
                }
                .onEnded { _ in
                    baselineViewport = nil
                }
        )
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
