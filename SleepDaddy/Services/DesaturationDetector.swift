import Foundation

/// Finds oxygen desaturations using a rolling baseline.
///
/// Conventional signal-processing parameters for making events visible on a chart. This
/// is **not** a clinical scoring implementation.
public struct DesaturationDetector: Sendable {
    /// A reading this far below the rolling baseline opens an event.
    public static let dropThreshold: Int = 4

    /// The baseline is the highest reading over this preceding window.
    public static let baselineWindow: TimeInterval = 120

    /// Events reaching below this are marked on the rail. Matches the first colour zone.
    public static let railNadirThreshold: UInt8 = 90

    private var baselineSampleCount: Int {
        Int(Self.baselineWindow / VitalsSession.sampleInterval)
    }

    public init() {}

    public func events(in session: VitalsSession) -> [DesaturationEvent] {
        let window = baselineSampleCount
        let count = session.sampleCount
        guard count > window else { return [] }

        var events: [DesaturationEvent] = []
        var index = window

        while index < count {
            guard let value = session.spo2Value(at: index),
                  let baseline = Self.baseline(in: session, endingBefore: index, window: window),
                  Int(baseline) - Int(value) >= Self.dropThreshold
            else {
                index += 1
                continue
            }

            // Walk to recovery, tracking the deepest point.
            var nadir = value
            var cursor = index
            while cursor < count,
                  let current = session.spo2Value(at: cursor),
                  Int(baseline) - Int(current) >= Self.dropThreshold {
                nadir = min(nadir, current)
                cursor += 1
            }

            events.append(DesaturationEvent(
                startDate: session.date(at: index),
                endDate: session.date(at: cursor),
                nadir: nadir,
                baseline: baseline
            ))

            index = cursor + 1
        }

        return events
    }

    /// Highest valid reading in the `window` samples before `index`. `nil` when the whole
    /// window is missing, so a sensor dropout cannot manufacture an event.
    private static func baseline(in session: VitalsSession, endingBefore index: Int, window: Int) -> UInt8? {
        var best: UInt8?
        for offset in max(0, index - window)..<index {
            if let value = session.spo2Value(at: offset) {
                best = max(best ?? value, value)
            }
        }
        return best
    }
}
