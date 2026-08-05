import Foundation

/// A continuous pulse-oximeter recording, held columnar.
///
/// Deliberately **not** `Codable`. The imported CSV is the durable representation;
/// conformance here would invite persisting a decoded form, which the design avoids
/// so that a parser fix repairs every recording already imported.
///
/// The device samples at an exact, jitter-free cadence, so no per-sample timestamp is
/// stored: sample `i` occurs at `startDate + i * sampleInterval`. That makes mapping a
/// viewport to a sample range arithmetic rather than a search.
public struct VitalsSession: Identifiable, Hashable, Sendable {
    /// The Checkme O2 Max records one sample every two seconds.
    public static let sampleInterval: TimeInterval = 2.0

    public let id: String
    public let startDate: Date
    /// `0` means "no reading". A live oximeter never reports zero saturation or zero
    /// pulse for a subject it is reading, so the sentinel is unambiguous.
    public let spo2: [UInt8]
    public let pulse: [UInt8]
    public let motion: [UInt8]
    public let sourceFileNames: [String]

    public init(
        id: String,
        startDate: Date,
        spo2: [UInt8],
        pulse: [UInt8],
        motion: [UInt8],
        sourceFileNames: [String]
    ) {
        self.id = id
        self.startDate = startDate
        self.spo2 = spo2
        self.pulse = pulse
        self.motion = motion
        self.sourceFileNames = sourceFileNames
    }

    public var sampleCount: Int { spo2.count }

    public var sampleInterval: TimeInterval { Self.sampleInterval }

    /// The instant of the final sample. A recording of `n` samples spans
    /// `(n - 1) * sampleInterval`, not `n * sampleInterval`.
    public var endDate: Date {
        guard sampleCount > 0 else { return startDate }
        return startDate.addingTimeInterval(Double(sampleCount - 1) * Self.sampleInterval)
    }

    public var dateInterval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }

    public func date(at index: Int) -> Date {
        startDate.addingTimeInterval(Double(index) * Self.sampleInterval)
    }

    /// The index of the sample containing `date`. May be negative or past `sampleCount`;
    /// callers clamp. Floors so a date inside a sample's two seconds maps to that sample.
    public func index(for date: Date) -> Int {
        Int(floor(date.timeIntervalSince(startDate) / Self.sampleInterval))
    }

    public func spo2Value(at index: Int) -> UInt8? {
        guard index >= 0, index < spo2.count else { return nil }
        let value = spo2[index]
        return value == 0 ? nil : value
    }

    public func pulseValue(at index: Int) -> UInt8? {
        guard index >= 0, index < pulse.count else { return nil }
        let value = pulse[index]
        return value == 0 ? nil : value
    }
}
