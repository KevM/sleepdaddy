import Foundation

/// One detected oxygen desaturation.
///
/// A signal-processing result for making events findable on a chart — **not** a clinical
/// score. Nothing in the app interprets, grades, or characterises these.
public struct DesaturationEvent: Identifiable, Hashable, Sendable {
    public var id: Date { startDate }

    public let startDate: Date
    public let endDate: Date
    public let nadir: UInt8
    public let baseline: UInt8

    public init(startDate: Date, endDate: Date, nadir: UInt8, baseline: UInt8) {
        self.startDate = startDate
        self.endDate = endDate
        self.nadir = nadir
        self.baseline = baseline
    }

    public var dropAmount: Int { Int(baseline) - Int(nadir) }

    public var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    /// Whether the rail marks this event. Aligned with the first colour-zone boundary so
    /// the design carries two thresholds, not three.
    public var reachesRailThreshold: Bool {
        nadir < DesaturationDetector.railNadirThreshold
    }
}
