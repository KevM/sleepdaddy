import SwiftUI

/// One min/max envelope lane. Used for both SpO₂ and pulse — they never share a lane,
/// because two scales on one plot is a dual-axis chart whose arbitrary scale alignment
/// invents correlations that are not in the data.
public struct VitalsEnvelopeLane: View {
    public enum Measure {
        case spo2
        case pulse
    }

    let envelope: VitalsEnvelope
    let measure: Measure
    let laneHeight: CGFloat

    public init(envelope: VitalsEnvelope, measure: Measure, laneHeight: CGFloat) {
        self.envelope = envelope
        self.measure = measure
        self.laneHeight = laneHeight
    }

    private var laneGeometry: VitalsLaneGeometry {
        switch measure {
        case .spo2: return .spo2(laneHeight: laneHeight)
        case .pulse: return .pulse(laneHeight: laneHeight)
        }
    }

    public var body: some View {
        Canvas { context, size in
            let scale = VitalsLaneGeometry(
                minValue: laneGeometry.minValue,
                maxValue: laneGeometry.maxValue,
                laneHeight: size.height
            )
            let columnWidth = size.width / CGFloat(max(1, envelope.columns.count))

            switch measure {
            case .spo2:
                drawZonedSpO2(context: context, size: size, scale: scale, columnWidth: columnWidth)
            case .pulse:
                drawPulse(context: context, size: size, scale: scale, columnWidth: columnWidth)
            }
        }
        .frame(height: laneHeight)
    }

    /// Colour follows the **value**, not the column, so a band crossing a threshold is
    /// coloured only in the part that crosses.
    private func drawZonedSpO2(
        context: GraphicsContext, size: CGSize,
        scale: VitalsLaneGeometry, columnWidth: CGFloat
    ) {
        for zone in VitalsColorZone.allCases {
            var path = Path()
            for (index, column) in envelope.columns.enumerated() {
                guard let low = column.spo2Min, let high = column.spo2Max else { continue }

                // Clip this column's span to the zone's value range.
                let zoneLow = zone.lowerBound.map { Double($0) } ?? scale.minValue
                let zoneHigh = zone.upperBound.map { Double($0) } ?? scale.maxValue
                let clippedLow = max(Double(low), zoneLow)
                let clippedHigh = min(Double(high), zoneHigh)
                guard clippedLow <= clippedHigh else { continue }

                let x = CGFloat(index) * columnWidth
                let top = scale.yPosition(for: clippedHigh)
                let bottom = scale.yPosition(for: clippedLow)
                path.addRect(CGRect(
                    x: x, y: top,
                    width: max(columnWidth, 1),
                    height: max(bottom - top, 1)
                ))
            }
            context.fill(path, with: .color(zone.color))
        }
    }

    private func drawPulse(
        context: GraphicsContext, size: CGSize,
        scale: VitalsLaneGeometry, columnWidth: CGFloat
    ) {
        var path = Path()
        for (index, column) in envelope.columns.enumerated() {
            guard let low = column.pulseMin, let high = column.pulseMax else { continue }
            let x = CGFloat(index) * columnWidth
            let top = scale.yPosition(for: high)
            let bottom = scale.yPosition(for: low)
            path.addRect(CGRect(
                x: x, y: top,
                width: max(columnWidth, 1),
                height: max(bottom - top, 1)
            ))
        }
        context.fill(path, with: .color(VitalsColorZone.pulseColor.opacity(0.65)))
    }
}
