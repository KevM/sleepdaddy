import SwiftUI

/// A thin rail marking desaturation events, drawn above the envelopes so clusters register
/// before the readings themselves are read.
public struct DesaturationRailView: View {
    let events: [DesaturationEvent]
    let geometry: SleepTimelineGeometry

    public static let railHeight: CGFloat = VitalsLanesLayout.railHeight

    public init(events: [DesaturationEvent], geometry: SleepTimelineGeometry) {
        self.events = events
        self.geometry = geometry
    }

    public var body: some View {
        Canvas { context, size in
            for event in events where event.reachesRailThreshold {
                let startX = geometry.xPosition(for: event.startDate)
                let endX = geometry.xPosition(for: event.endDate)
                // A brief event can be sub-pixel; give it a floor so it stays visible.
                let width = max(2, endX - startX)
                guard endX >= 0, startX <= size.width else { continue }

                let rect = CGRect(x: startX, y: 0, width: width, height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: size.height / 2),
                    with: .color(VitalsColorZone.critical.color)
                )
            }
        }
        .frame(height: Self.railHeight)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let marked = events.filter(\.reachesRailThreshold)
        guard !marked.isEmpty else { return "No oxygen events below 90 percent" }
        let lowest = marked.map(\.nadir).min() ?? 0
        return "\(marked.count) oxygen events below 90 percent, lowest \(lowest) percent"
    }
}
