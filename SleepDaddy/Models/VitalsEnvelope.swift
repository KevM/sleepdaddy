import Foundation

/// Per-pixel-column extremes for one viewport. Render output — never persisted.
public struct VitalsEnvelope: Equatable, Sendable {
    public struct Column: Equatable, Sendable {
        public let spo2Min: UInt8?
        public let spo2Max: UInt8?
        public let pulseMin: UInt8?
        public let pulseMax: UInt8?

        public init(spo2Min: UInt8?, spo2Max: UInt8?, pulseMin: UInt8?, pulseMax: UInt8?) {
            self.spo2Min = spo2Min
            self.spo2Max = spo2Max
            self.pulseMin = pulseMin
            self.pulseMax = pulseMax
        }

        public static let empty = Column(spo2Min: nil, spo2Max: nil, pulseMin: nil, pulseMax: nil)

        /// A column with no readings. Drawn as a gap, never bridged.
        public var isEmpty: Bool { spo2Min == nil && pulseMin == nil }
    }

    public let columns: [Column]

    public init(columns: [Column]) {
        self.columns = columns
    }
}
