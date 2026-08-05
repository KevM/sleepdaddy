import CoreGraphics
import Foundation

/// Maps a vitals reading to a y offset inside one lane.
///
/// Deliberately narrow: x comes from `SleepTimelineGeometry`, unchanged and shared with
/// the stage plot. One geometry driving both is what keeps the lanes locked together
/// through pinch and pan with no synchronisation code.
public struct VitalsLaneGeometry: Equatable, Sendable {
    public let minValue: Double
    public let maxValue: Double
    public let laneHeight: CGFloat

    public init(minValue: Double, maxValue: Double, laneHeight: CGFloat) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.laneHeight = laneHeight
    }

    /// SpO₂ lane: 70–100%.
    public static func spo2(laneHeight: CGFloat) -> Self {
        Self(minValue: 70, maxValue: 100, laneHeight: laneHeight)
    }

    /// Pulse lane: 30–110 bpm. Separate lane, separate scale — never shared with SpO₂.
    /// Two measures of different scale on one plot is a dual-axis chart, whose arbitrary
    /// scale alignment invents correlations that are not in the data.
    public static func pulse(laneHeight: CGFloat) -> Self {
        Self(minValue: 30, maxValue: 110, laneHeight: laneHeight)
    }

    public func yPosition(for value: Double) -> CGFloat {
        let span = maxValue - minValue
        guard span > 0 else { return laneHeight / 2 }
        let clamped = Swift.min(Swift.max(value, minValue), maxValue)
        let ratio = (clamped - minValue) / span
        return laneHeight - CGFloat(ratio) * laneHeight
    }

    public func yPosition(for value: Int) -> CGFloat {
        yPosition(for: Double(value))
    }

    public func yPosition(for value: UInt8) -> CGFloat {
        yPosition(for: Double(value))
    }
}
