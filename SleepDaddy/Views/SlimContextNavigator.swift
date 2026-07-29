import SwiftUI

public struct SlimContextNavigator: View {
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date
    let onUpdateViewport: (TimelineViewport) -> Void

    @State private var baselineViewport: TimelineViewport?

    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        onUpdateViewport: @escaping (TimelineViewport) -> Void
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.onUpdateViewport = onUpdateViewport
    }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let trackHeight: CGFloat = 14

                let currentViewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
                let geom = SleepTimelineGeometry(
                    totalStart: night.timelineStart,
                    totalEnd: night.timelineEnd,
                    viewport: currentViewport,
                    canvasWidth: width,
                    canvasHeight: height
                )

                let coreX1 = geom.navigatorXRatio(for: night.coreWindowStart) * width
                let coreX2 = geom.navigatorXRatio(for: night.coreWindowEnd) * width

                let vpX1 = geom.navigatorXRatio(for: viewportStart) * width
                let vpX2 = geom.navigatorXRatio(for: viewportEnd) * width
                let vpWidth = max(8.0, vpX2 - vpX1)

                ZStack(alignment: .leading) {
                    // Transparent container for full 44pt interactive hit target
                    Color.clear

                    // Track visual element centered within 44pt height
                    ZStack(alignment: .leading) {
                        // Full detected background track
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: trackHeight)

                        // Core window demarcation region
                        Capsule()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: max(trackHeight, coreX2 - coreX1), height: trackHeight)
                            .offset(x: coreX1)

                        // Visible viewport handle
                        Capsule()
                            .fill(Color.accentColor.opacity(0.35))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            )
                            .frame(width: max(trackHeight, vpWidth), height: trackHeight)
                            .shadow(color: Color.accentColor.opacity(0.25), radius: 3, y: 1)
                            .offset(x: vpX1)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let baseline: TimelineViewport
                            if let b = baselineViewport {
                                baseline = b
                            } else {
                                let touchX = value.startLocation.x
                                let isInside = touchX >= vpX1 && touchX <= (vpX1 + vpWidth)
                                if isInside {
                                    baseline = currentViewport
                                } else {
                                    baseline = geom.navigatorViewport(
                                        currentViewport,
                                        centeredAtX: touchX,
                                        navigatorWidth: width
                                    )
                                    onUpdateViewport(baseline)
                                }
                                baselineViewport = baseline
                            }

                            let deltaX = value.translation.width
                            let updated = geom.navigatorViewport(
                                baseline,
                                translatedBy: deltaX,
                                navigatorWidth: width
                            )
                            onUpdateViewport(updated)
                        }
                        .onEnded { _ in
                            baselineViewport = nil
                        }
                )
            }
            .frame(height: 44)

            // Labels for start and end times
            HStack {
                Text(timeFormatter.string(from: night.timelineStart))
                if night.isExtended {
                    Text("(Extended)")
                        .foregroundColor(.orange)
                        .font(.caption2)
                }
                Spacer()
                Text("Core: \(timeFormatter.string(from: night.coreWindowStart)) - \(timeFormatter.string(from: night.coreWindowEnd))")
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeFormatter.string(from: night.timelineEnd))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline navigator from \(timeFormatter.string(from: night.timelineStart)) to \(timeFormatter.string(from: night.timelineEnd))")
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }
}
