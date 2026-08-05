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

        var bytes = [UInt8](data)
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            bytes.removeFirst(3)
        }

        let lines = Self.splitLines(bytes)
        guard let headerLine = lines.first else { throw VitalsImportError.emptyFile }

        let header = String(decoding: bytes[headerLine], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        guard Self.isValidHeader(header) else {
            throw VitalsImportError.unrecognisedHeader(found: header)
        }

        let dataLines = lines.dropFirst()
        guard !dataLines.isEmpty else { throw VitalsImportError.noDataRows }

        var spo2 = [UInt8](); spo2.reserveCapacity(dataLines.count)
        var pulse = [UInt8](); pulse.reserveCapacity(dataLines.count)
        var motion = [UInt8](); motion.reserveCapacity(dataLines.count)

        var startDate: Date?
        var lastTimestampText: Substring = ""
        let trimSet = CharacterSet(charactersIn: " \"'\t\r\n\u{FEFF}")

        for (offset, range) in dataLines.enumerated() {
            let fields = Self.splitFields(bytes, range)
            guard fields.count >= 4 else {
                throw VitalsImportError.malformedRow(line: offset + 2)
            }

            if startDate == nil {
                let text = String(decoding: bytes[fields[0]], as: UTF8.self)
                    .trimmingCharacters(in: trimSet)
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
        let trimmedLast = String(lastTimestampText).trimmingCharacters(in: trimSet)
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

    public static func isValidHeader(_ header: String) -> Bool {
        let clean = header.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        if clean == expectedHeader { return true }

        let columns = clean.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'\t\r\n\u{FEFF}")).lowercased() }

        guard columns.count >= 4 else { return false }

        let col0 = columns[0]
        let col1 = columns[1]
        let col2 = columns[2]
        let col3 = columns[3]

        let isCol0Time = col0.contains("time") || col0.contains("stamp") || col0.contains("date")
        let isCol1Oxygen = col1.contains("oxygen") || col1.contains("spo2") || col1.contains("o2")
        let isCol2Pulse = col2.contains("pulse") || col2.contains("pr") || col2.contains("heart") || col2.contains("hr")
        let isCol3Motion = col3.contains("motion") || col3.contains("activity") || col3.contains("vibration") || col3.contains("move") || col3.contains("step") || col3.contains("mark")

        return isCol0Time && isCol1Oxygen && isCol2Pulse && isCol3Motion
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
            } else if byte == 0x20 || byte == 0x0D || byte == 0x22 || byte == 0x27 {
                continue
            } else {
                return nil
            }
        }
        return sawDigit ? UInt8(value) : nil
    }
}
