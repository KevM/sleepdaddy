import SwiftUI

/// Value bands for colouring the SpO₂ lane.
///
/// Colour re-encodes what vertical position already shows. That redundancy is deliberate:
/// the SpO₂ lane carries a single series, so the identity channel is free, and severe dips
/// are narrow at low zoom where position alone is easy to miss.
///
/// **Green is deliberately absent.** Status green against status orange measures ΔE 5.6
/// under protanopia (target 8) — roughly 1 in 12 men would see the normal and concerning
/// bands as nearly the same colour. Using the series blue for the normal band takes the
/// worst adjacent pair to ΔE 24.4. Three bands rather than four because status warning
/// against status serious measures ΔE 13.6 under *normal* vision, below the floor of 15.
///
/// There is no equivalent for pulse. SpO₂ has broadly agreed reference ranges; a sleeping
/// heart rate does not, and a low rate is equally consistent with athletic bradycardia or
/// with a real finding. Colouring it would assert a judgement the data cannot support.
public enum VitalsColorZone: String, CaseIterable, Sendable {
    case normal
    case warning
    case critical

    public static let normalLowerBound: UInt8 = 90
    public static let warningLowerBound: UInt8 = 85

    public static func zone(forSpO2 value: UInt8) -> VitalsColorZone {
        if value >= normalLowerBound { return .normal }
        if value >= warningLowerBound { return .warning }
        return .critical
    }

    public func contains(spo2 value: UInt8) -> Bool {
        Self.zone(forSpO2: value) == self
    }

    /// The lowest value in this zone, and the exclusive upper edge. `nil` upper means
    /// "no ceiling"; `nil` lower means "no floor".
    public var lowerBound: UInt8? {
        switch self {
        case .normal: return Self.normalLowerBound
        case .warning: return Self.warningLowerBound
        case .critical: return nil
        }
    }

    public var upperBound: UInt8? {
        switch self {
        case .normal: return nil
        case .warning: return Self.normalLowerBound
        case .critical: return Self.warningLowerBound
        }
    }

    /// Numeric, never a verdict. The threshold is a display choice; the word would be an
    /// interpretation, and interpreting the data is an explicit non-goal.
    public var legendLabel: String {
        switch self {
        case .normal: return "90% and above"
        case .warning: return "85–90%"
        case .critical: return "Below 85%"
        }
    }

    public var color: Color {
        switch self {
        case .normal: return Color(red: 0.165, green: 0.471, blue: 0.839)   // #2a78d6 series blue
        case .warning: return Color(red: 0.980, green: 0.698, blue: 0.098)  // #fab219 status warning
        case .critical: return Color(red: 0.816, green: 0.231, blue: 0.231) // #d03b3b status critical
        }
    }

    /// The pulse lane is a single hue with no zones.
    public static let pulseColor = Color(red: 0.165, green: 0.471, blue: 0.839) // #2a78d6
}
