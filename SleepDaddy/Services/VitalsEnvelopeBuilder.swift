import Foundation

/// Reduces a full sample array to one min/max pair per pixel column.
///
/// **Both extremes are kept.** Averaging a column would erase brief severe events: a
/// 38-second dip to 73% averaged against surrounding 95% readings renders near 91% and
/// vanishes. Keeping the minimum costs nothing and draws 73% at 73%, so zooming out
/// narrows an event's width but never softens its depth.
///
/// Runs per frame against the complete session. At roughly 22,000 samples a full scan is
/// inexpensive, so there is no resolution pyramid and no cache. If a future multi-night
/// view makes the cost real, a cache goes behind this type without touching callers.
public struct VitalsEnvelopeBuilder: Sendable {
    public init() {}

    public func build(
        session: VitalsSession,
        viewport: TimelineViewport,
        pixelWidth: Int
    ) -> VitalsEnvelope {
        guard pixelWidth > 0 else { return VitalsEnvelope(columns: []) }

        let sampleCount = session.sampleCount
        guard sampleCount > 0 else {
            return VitalsEnvelope(columns: Array(repeating: .empty, count: pixelWidth))
        }

        var columns: [VitalsEnvelope.Column] = []
        columns.reserveCapacity(pixelWidth)

        let viewportSeconds = max(viewport.duration, .leastNonzeroMagnitude)

        for column in 0..<pixelWidth {
            // The time slice this column covers, converted to sample indices.
            let fromRatio = Double(column) / Double(pixelWidth)
            let toRatio = Double(column + 1) / Double(pixelWidth)
            let columnStart = viewport.start.addingTimeInterval(viewportSeconds * fromRatio)
            let columnEnd = viewport.start.addingTimeInterval(viewportSeconds * toRatio)

            var lower = session.index(for: columnStart)
            var upper = session.index(for: columnEnd) + 1

            // Zoomed past 1:1 the slice can be narrower than one sample. Hold the
            // containing sample so the lane draws a step rather than a gap.
            if upper <= lower { upper = lower + 1 }

            lower = max(0, lower)
            upper = min(sampleCount, upper)

            guard lower < upper else {
                columns.append(.empty)
                continue
            }

            var spo2Min: UInt8?
            var spo2Max: UInt8?
            var pulseMin: UInt8?
            var pulseMax: UInt8?

            for index in lower..<upper {
                let oxygen = session.spo2[index]
                if oxygen != 0 {
                    spo2Min = min(spo2Min ?? oxygen, oxygen)
                    spo2Max = max(spo2Max ?? oxygen, oxygen)
                }
                let rate = session.pulse[index]
                if rate != 0 {
                    pulseMin = min(pulseMin ?? rate, rate)
                    pulseMax = max(pulseMax ?? rate, rate)
                }
            }

            columns.append(VitalsEnvelope.Column(
                spo2Min: spo2Min, spo2Max: spo2Max,
                pulseMin: pulseMin, pulseMax: pulseMax
            ))
        }

        return VitalsEnvelope(columns: columns)
    }
}
