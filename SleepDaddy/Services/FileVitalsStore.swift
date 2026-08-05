import Foundation

/// Stores each imported CSV compressed and losslessly in Application Support.
///
/// Decompression reproduces the imported file byte for byte, so reparsing always works
/// and a parser fix repairs every recording already imported. No decoded form is
/// persisted, which is what removes the schema-migration problem entirely.
///
/// `NSData.compressed(using:)` exposes no compression level — the Compression framework
/// chooses. Measured output lands close to the zlib-6 figure in the design document.
public struct FileVitalsStore: VitalsStore {
    public enum StoreError: Error, Equatable, Sendable {
        case couldNotCreateDirectory
        case couldNotReadRecording
    }

    private static let fileExtension = "csv.z"

    private let directory: URL
    private let calendar: Calendar
    private let parser: CheckmeCSVParser

    public init(directory: URL? = nil, calendar: Calendar = .current) throws {
        let resolved: URL
        if let directory {
            resolved = directory
        } else {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else {
                throw StoreError.couldNotCreateDirectory
            }
            resolved = support.appendingPathComponent("Vitals", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        self.directory = resolved
        self.calendar = calendar
        self.parser = CheckmeCSVParser(calendar: calendar)
    }

    // MARK: - Import

    @discardableResult
    public func importRecording(_ data: Data, originalName: String) throws -> VitalsRecordingDescriptor {
        // Parse before writing so a file that cannot be read never enters the store.
        let session = try parser.parse(data, fileName: originalName)

        let url = directory.appendingPathComponent(
            "\(Self.stamp(session.startDate))_\(Self.stamp(session.endDate)).\(Self.fileExtension)"
        )
        let descriptor = VitalsRecordingDescriptor(
            start: session.startDate, end: session.endDate, url: url
        )

        // The span-derived name is the dedup key: the same recording lands on the same
        // path regardless of what the exporting app called it.
        guard !FileManager.default.fileExists(atPath: url.path) else { return descriptor }

        let compressed = try (data as NSData).compressed(using: .zlib)
        try compressed.write(to: url)
        return descriptor
    }

    // MARK: - Lookup

    public func allDescriptors() throws -> [VitalsRecordingDescriptor] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return contents
            .compactMap(Self.descriptor(from:))
            .sorted { $0.start < $1.start }
    }

    public func descriptors(overlapping interval: DateInterval) throws -> [VitalsRecordingDescriptor] {
        try allDescriptors().filter { $0.dateInterval.intersects(interval) }
    }

    // MARK: - Load

    public func loadSession(for descriptor: VitalsRecordingDescriptor) throws -> VitalsSession {
        let csv = try originalCSV(for: descriptor)
        return try parser.parse(csv, fileName: descriptor.url.lastPathComponent)
    }

    public func originalCSV(for descriptor: VitalsRecordingDescriptor) throws -> Data {
        let stored = try Data(contentsOf: descriptor.url)
        return try (stored as NSData).decompressed(using: .zlib) as Data
    }

    // MARK: - File naming

    /// `20260803T180248` — no separators that a file system would object to.
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private static func date(fromStamp stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.date(from: stamp)
    }

    private static func descriptor(from url: URL) -> VitalsRecordingDescriptor? {
        let name = url.lastPathComponent
        guard name.hasSuffix("." + fileExtension) else { return nil }
        let base = String(name.dropLast(fileExtension.count + 1))
        let parts = base.split(separator: "_")
        guard parts.count == 2,
              let start = date(fromStamp: String(parts[0])),
              let end = date(fromStamp: String(parts[1]))
        else { return nil }
        return VitalsRecordingDescriptor(start: start, end: end, url: url)
    }
}
