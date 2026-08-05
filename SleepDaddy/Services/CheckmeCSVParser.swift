import Foundation

public enum VitalsImportError: Error, Equatable, Sendable {
    case emptyFile
    case unrecognisedHeader(found: String)
    case noDataRows
    case unparseableTimestamp(line: Int, text: String)
    case cadenceViolation(expected: Date, found: Date)
    case malformedRow(line: Int)

    public var userMessage: String {
        switch self {
        case .emptyFile:
            return "That file is empty."
        case .unrecognisedHeader:
            return "That doesn't look like a Checkme O2 Max export — the column headings don't match."
        case .noDataRows:
            return "That file has headings but no readings."
        case .unparseableTimestamp(let line, _):
            return "The time on line \(line) couldn't be read."
        case .cadenceViolation:
            return "That recording's timing isn't the expected 2-second interval."
        case .malformedRow(let line):
            return "Line \(line) is incomplete."
        }
    }
}

/// Parses a Checkme O2 Max CSV export into a `VitalsSession`.
///
/// Pure — takes bytes, returns a value, performs no I/O.
///
/// **Only two timestamps are parsed**, the first and the last. Every other sample's
/// instant is derived arithmetically from the fixed cadence, and the last row is checked
/// against that arithmetic. Parsing a timestamp per row would cost roughly a second per
/// file and is guarded by a performance test.
public struct CheckmeCSVParser: Sendable {
    public static let expectedHeader = "Time,Oxygen Level,Pulse Rate,Motion,O2 Reminder,PR Reminder"

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ data: Data, fileName: String) throws -> VitalsSession {
        guard !data.isEmpty else { throw VitalsImportError.emptyFile }

        let bytes = [UInt8](data)
        let lines = Self.splitLines(bytes)
        guard let headerLine = lines.first else { throw VitalsImportError.emptyFile }

        let header = String(decoding: bytes[headerLine], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        guard header == Self.expectedHeader else {
            throw VitalsImportError.unrecognisedHeader(found: header)
        }

        let dataLines = lines.dropFirst()
        guard !dataLines.isEmpty else { throw VitalsImportError.noDataRows }

        var spo2 = [UInt8](); spo2.reserveCapacity(dataLines.count)
        var pulse = [UInt8](); pulse.reserveCapacity(dataLines.count)
        var motion = [UInt8](); motion.reserveCapacity(dataLines.count)

        var startDate: Date?
        var lastTimestampText: Substring = ""

        for (offset, range) in dataLines.enumerated() {
            let fields = Self.splitFields(bytes, range)
            guard fields.count >= 4 else {
                throw VitalsImportError.malformedRow(line: offset + 2)
            }

            if startDate == nil {
                let text = String(decoding: bytes[fields[0]], as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces)
                guard let parsed = CheckmeTimestamp.parse(text, calendar: calendar) else {
                    throw VitalsImportError.unparseableTimestamp(line: offset + 2, text: text)
                }
                startDate = parsed
            }

            spo2.append(Self.parseByte(bytes, fields[1]) ?? 0)
            pulse.append(Self.parseByte(bytes, fields[2]) ?? 0)
            motion.append(Self.parseByte(bytes, fields[3]) ?? 0)

            if offset == dataLines.count - 1 {
                lastTimestampText = Substring(String(decoding: bytes[fields[0]], as: UTF8.self))
            }
        }

        guard let start = startDate else { throw VitalsImportError.noDataRows }

        let expectedEnd = start.addingTimeInterval(Double(spo2.count - 1) * VitalsSession.sampleInterval)
        let trimmedLast = lastTimestampText.trimmingCharacters(in: .whitespaces)
        guard let actualEnd = CheckmeTimestamp.parse(trimmedLast, calendar: calendar) else {
            throw VitalsImportError.unparseableTimestamp(line: dataLines.count + 1, text: trimmedLast)
        }
        guard abs(actualEnd.timeIntervalSince(expectedEnd)) < 1 else {
            throw VitalsImportError.cadenceViolation(expected: expectedEnd, found: actualEnd)
        }

        return VitalsSession(
            id: fileName,
            startDate: start,
            spo2: spo2,
            pulse: pulse,
            motion: motion,
            sourceFileNames: [fileName]
        )
    }

    // MARK: - Byte scanning

    /// Line ranges, skipping empty lines (which a trailing newline produces).
    private static func splitLines(_ bytes: [UInt8]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var lineStart = 0
        for index in bytes.indices where bytes[index] == 0x0A {
            var lineEnd = index
            if lineEnd > lineStart, bytes[lineEnd - 1] == 0x0D { lineEnd -= 1 }
            if lineEnd > lineStart { ranges.append(lineStart..<lineEnd) }
            lineStart = index + 1
        }
        if lineStart < bytes.count {
            var lineEnd = bytes.count
            if lineEnd > lineStart, bytes[lineEnd - 1] == 0x0D { lineEnd -= 1 }
            if lineEnd > lineStart { ranges.append(lineStart..<lineEnd) }
        }
        return ranges
    }

    private static func splitFields(_ bytes: [UInt8], _ line: Range<Int>) -> [Range<Int>] {
        var fields: [Range<Int>] = []
        var fieldStart = line.lowerBound
        for index in line where bytes[index] == 0x2C {
            fields.append(fieldStart..<index)
            fieldStart = index + 1
        }
        fields.append(fieldStart..<line.upperBound)
        return fields
    }

    /// Returns `nil` for the `--` sentinel or anything non-numeric; the caller stores 0.
    private static func parseByte(_ bytes: [UInt8], _ range: Range<Int>) -> UInt8? {
        var value = 0
        var sawDigit = false
        for index in range {
            let byte = bytes[index]
            if byte >= 0x30 && byte <= 0x39 {
                value = value * 10 + Int(byte - 0x30)
                sawDigit = true
                if value > 255 { return 255 }
            } else if byte == 0x20 || byte == 0x0D {
                continue
            } else {
                return nil
            }
        }
        return sawDigit ? UInt8(value) : nil
    }
}
