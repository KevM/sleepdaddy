import Foundation

/// A stored recording, identified entirely by its file name.
///
/// The name carries the span, so answering "which recordings cover this night?" needs no
/// parsing, no decompression, and no sidecar index to keep consistent.
public struct VitalsRecordingDescriptor: Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let url: URL

    public init(start: Date, end: Date, url: URL) {
        self.start = start
        self.end = end
        self.url = url
    }

    public var dateInterval: DateInterval {
        DateInterval(start: start, end: end)
    }
}

/// Durable storage for imported recordings.
///
/// The protocol is the iCloud seam: a synchronising implementation is a new conformance,
/// and callers do not change.
public protocol VitalsStore: Sendable {
    @discardableResult
    func importRecording(_ data: Data, originalName: String) throws -> VitalsRecordingDescriptor
    func allDescriptors() throws -> [VitalsRecordingDescriptor]
    func descriptors(overlapping interval: DateInterval) throws -> [VitalsRecordingDescriptor]
    func loadSession(for descriptor: VitalsRecordingDescriptor) throws -> VitalsSession
    func originalCSV(for descriptor: VitalsRecordingDescriptor) throws -> Data
}

public extension VitalsStore {
    /// The stitched session covering a night, or `nil` when nothing overlaps.
    func session(covering interval: DateInterval) throws -> VitalsSession? {
        let descriptors = try descriptors(overlapping: interval)
        guard !descriptors.isEmpty else { return nil }
        let sessions = try descriptors.map { try loadSession(for: $0) }
        return VitalsSessionStitcher().stitch(sessions).max { $0.sampleCount < $1.sampleCount }
    }
}
