import Foundation

/// Joins recordings the device split at its ten-hour session cap back into one session.
///
/// Runs at **load time**. Stored files are never merged or rewritten — each stays exactly
/// as exported.
public struct VitalsSessionStitcher: Sendable {
    /// Recordings whose boundaries fall within this window are one recording. The real
    /// device gap is 4 seconds; a genuine separate recording is hours away.
    public static let maximumJoinGap: TimeInterval = 5 * 60

    public init() {}

    public func stitch(_ sessions: [VitalsSession]) -> [VitalsSession] {
        guard !sessions.isEmpty else { return [] }

        let ordered = sessions.sorted { $0.startDate < $1.startDate }
        var result: [VitalsSession] = []
        var current = ordered[0]

        for next in ordered.dropFirst() {
            let gap = next.startDate.timeIntervalSince(current.endDate)
            if gap >= 0 && gap <= Self.maximumJoinGap {
                current = Self.join(current, next)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    /// Concatenates `next` onto `first`, padding the gap with missing samples so that
    /// index arithmetic stays true for the whole joined session. Without the padding,
    /// every sample after the join would report an instant earlier than it occurred.
    private static func join(_ first: VitalsSession, _ next: VitalsSession) -> VitalsSession {
        let gapSeconds = next.startDate.timeIntervalSince(first.endDate)
        let padCount = max(0, Int(round(gapSeconds / VitalsSession.sampleInterval)) - 1)
        let pad = [UInt8](repeating: 0, count: padCount)

        return VitalsSession(
            id: first.id,
            startDate: first.startDate,
            spo2: first.spo2 + pad + next.spo2,
            pulse: first.pulse + pad + next.pulse,
            motion: first.motion + pad + next.motion,
            sourceFileNames: first.sourceFileNames + next.sourceFileNames
        )
    }
}
