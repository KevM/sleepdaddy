# Pulse Oximeter Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import Checkme O2 Max CSV exports and draw SpO₂, pulse, and desaturation events as lanes beneath the existing sleep-stage timeline, sharing one time axis.

**Architecture:** Vitals resolve in parallel with sleep — `NightAssembler` is not modified. The imported CSV is stored compressed and verbatim as the source of truth and parsed on night selection. Rendering reduces the full sample array to a per-pixel min/max envelope every frame, so brief severe desaturations survive at every zoom level.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`import Testing`), XcodeGen, iOS 18 target.

**Spec:** [docs/superpowers/specs/2026-08-04-pulse-oximeter-integration-design.md](../specs/2026-08-04-pulse-oximeter-integration-design.md)

---

## Before You Start

**Build and test commands** (from `AGENTS.md`):

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Single suite:

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/CheckmeCSVParserTests
```

**Two warnings about this toolchain:**

1. `xcodebuild` prints `TEST SUCCEEDED` even when the test runner crashed and was relaunched. Do not trust the summary line alone — scan the output for `Restarting after unexpected exit` or a suite that reported zero tests. If a suite you just wrote does not appear in the output, it did not run.
2. Test runs are slow. Batch them: write several tests, then run the suite once. The plan groups steps accordingly.

**Do not commit** `SleepDaddy.xcodeproj` or `Info.plist` — they are generated. After any `project.yml` change run `xcodegen generate`.

---

## File Structure

**New — `SleepDaddy/Models/`**

| File | Responsibility |
| --- | --- |
| `VitalsSession.swift` | Columnar sample storage, runtime only, not `Codable` |
| `DesaturationEvent.swift` | One detected event: span, nadir, baseline |
| `VitalsEnvelope.swift` | Per-pixel min/max render output |
| `VitalsColorZone.swift` | Three-zone SpO₂ colour mapping and legend labels |

**New — `SleepDaddy/Services/`**

| File | Responsibility |
| --- | --- |
| `CheckmeTimestamp.swift` | Parses `18:02:48 Aug 03 2026` without `DateFormatter` |
| `CheckmeCSVParser.swift` | CSV bytes → `VitalsSession`; pure, no I/O |
| `VitalsSessionStitcher.swift` | Joins sessions within 5 minutes |
| `VitalsEnvelopeBuilder.swift` | Viewport + width → `VitalsEnvelope` |
| `DesaturationDetector.swift` | `VitalsSession` → `[DesaturationEvent]` |
| `VitalsStore.swift` | `VitalsStore` protocol + `VitalsRecordingDescriptor` |
| `FileVitalsStore.swift` | Compressed CSV files in Application Support |

**New — `SleepDaddy/Layout/`**

| File | Responsibility |
| --- | --- |
| `VitalsLaneGeometry.swift` | Value → y only; x comes from `SleepTimelineGeometry` |

**New — `SleepDaddy/Views/`**

| File | Responsibility |
| --- | --- |
| `VitalsLanesView.swift` | Composes the rail + two lanes below the stage plot |
| `DesaturationRailView.swift` | The event rail |
| `VitalsEnvelopeLane.swift` | One envelope lane (used for both SpO₂ and pulse) |
| `VitalsImportButton.swift` | `fileImporter` entry point |

**Modified**

| File | Change |
| --- | --- |
| `SleepDaddy/Models/AssembledNight.swift` | `vitalsExtent`; data-defined `timelineStart`/`timelineEnd` |
| `SleepDaddy/ViewModels/NightBrowserModel.swift` | Loads vitals for the selected night |
| `SleepDaddy/Views/SelectedNightDetailView.swift` | Composes `VitalsLanesView` |
| `SleepDaddy/Views/SettingsView.swift` | Import entry point |
| `SleepDaddy/SleepDaddyApp.swift` | `onOpenURL` |
| `project.yml` | CSV document type |
| `SleepDaddyTests/NightAssemblerTests.swift` | Updated for data-defined extent |
| `SleepDaddyTests/SleepTimelineGeometryTests.swift` | Updated for data-defined extent |

---

## Task 1: VitalsSession model

**Files:**
- Create: `SleepDaddy/Models/VitalsSession.swift`
- Test: `SleepDaddyTests/VitalsSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/VitalsSessionTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct VitalsSessionTests {
    private func makeSession(count: Int, start: Date = Date(timeIntervalSinceReferenceDate: 0)) -> VitalsSession {
        VitalsSession(
            id: "test",
            startDate: start,
            spo2: Array(repeating: UInt8(95), count: count),
            pulse: Array(repeating: UInt8(60), count: count),
            motion: Array(repeating: UInt8(0), count: count),
            sourceFileNames: ["a.csv"]
        )
    }

    @Test func sampleCountReflectsTheColumns() {
        #expect(makeSession(count: 10).sampleCount == 10)
    }

    @Test func endDateIsDerivedFromTheFixedCadence() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        // 10 samples at 2s: the last sample sits 18s after the first.
        #expect(session.endDate == start.addingTimeInterval(18))
    }

    @Test func dateForIndexUsesArithmeticNotStoredTimestamps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        #expect(session.date(at: 0) == start)
        #expect(session.date(at: 5) == start.addingTimeInterval(10))
    }

    @Test func indexForDateFloorsIntoTheContainingSample() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        #expect(session.index(for: start) == 0)
        #expect(session.index(for: start.addingTimeInterval(1.9)) == 0)
        #expect(session.index(for: start.addingTimeInterval(2.0)) == 1)
        #expect(session.index(for: start.addingTimeInterval(-5)) == -2)
    }

    @Test func zeroMeansMissing() {
        let session = VitalsSession(
            id: "t", startDate: Date(timeIntervalSinceReferenceDate: 0),
            spo2: [95, 0, 96], pulse: [60, 0, 61], motion: [0, 0, 0],
            sourceFileNames: []
        )
        #expect(session.spo2Value(at: 0) == 95)
        #expect(session.spo2Value(at: 1) == nil)
        #expect(session.pulseValue(at: 1) == nil)
    }

    @Test func dateIntervalSpansTheWholeRecording() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = makeSession(count: 10, start: start)
        #expect(session.dateInterval.start == start)
        #expect(session.dateInterval.end == start.addingTimeInterval(18))
    }
}
```

- [ ] **Step 2: Write the implementation**

Create `SleepDaddy/Models/VitalsSession.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/VitalsSessionTests
```

Expected: 6 tests pass. Confirm `VitalsSessionTests` appears by name in the output.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Models/VitalsSession.swift SleepDaddyTests/VitalsSessionTests.swift
git commit -m "feat: add VitalsSession columnar sample model"
```

---

## Task 2: Timestamp parsing without DateFormatter

**Files:**
- Create: `SleepDaddy/Services/CheckmeTimestamp.swift`
- Test: `SleepDaddyTests/CheckmeTimestampTests.swift`

`DateFormatter` costs roughly 10–50 µs per call. At 22,000 rows that is most of a second on every night change. The parser calls this **twice per file** — first row and last row — and derives every other timestamp arithmetically.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/CheckmeTimestampTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct CheckmeTimestampTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    @Test func parsesTheDeviceFormat() throws {
        let date = try #require(CheckmeTimestamp.parse("18:02:48 Aug 03 2026", calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 3)
        #expect(parts.hour == 18)
        #expect(parts.minute == 2)
        #expect(parts.second == 48)
    }

    @Test func parsesEveryMonthAbbreviation() {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        for (offset, name) in names.enumerated() {
            let parsed = CheckmeTimestamp.parse("00:00:00 \(name) 01 2026", calendar: calendar)
            #expect(parsed != nil, "month \(name) failed to parse")
            let month = calendar.dateComponents([.month], from: parsed!).month
            #expect(month == offset + 1)
        }
    }

    @Test func parsesAcrossMidnight() throws {
        let before = try #require(CheckmeTimestamp.parse("23:59:58 Aug 03 2026", calendar: calendar))
        let after = try #require(CheckmeTimestamp.parse("00:00:00 Aug 04 2026", calendar: calendar))
        #expect(after.timeIntervalSince(before) == 2)
    }

    @Test func rejectsMalformedInput() {
        #expect(CheckmeTimestamp.parse("", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("18:02:48 Aug 03", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("18:02 Aug 03 2026", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("18:02:48 Xyz 03 2026", calendar: calendar) == nil)
        #expect(CheckmeTimestamp.parse("aa:bb:cc Aug 03 2026", calendar: calendar) == nil)
    }
}
```

- [ ] **Step 2: Write the implementation**

Create `SleepDaddy/Services/CheckmeTimestamp.swift`:

```swift
import Foundation

/// Parses the Checkme O2 Max timestamp format: `18:02:48 Aug 03 2026`.
///
/// The format carries **no timezone**, so values are resolved in the supplied calendar's
/// zone — the device's current zone in production. See the design document's timezone
/// limitation.
///
/// `DateFormatter` is deliberately not used: it costs roughly 10–50 µs per call, and a
/// full recording is 22,000 rows. `CheckmeCSVParser` calls this exactly twice per file.
public enum CheckmeTimestamp {
    private static let monthNames = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12
    ]

    public static func parse(_ text: Substring, calendar: Calendar) -> Date? {
        let fields = text.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 4 else { return nil }

        let clock = fields[0].split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 3,
              let hour = Int(clock[0]),
              let minute = Int(clock[1]),
              let second = Int(clock[2]),
              let month = monthNames[String(fields[1])],
              let day = Int(fields[2]),
              let year = Int(fields[3])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }

    public static func parse(_ text: String, calendar: Calendar) -> Date? {
        parse(text[text.startIndex...], calendar: calendar)
    }
}
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/CheckmeTimestampTests
```

Expected: 4 tests pass.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Services/CheckmeTimestamp.swift SleepDaddyTests/CheckmeTimestampTests.swift
git commit -m "feat: add DateFormatter-free Checkme timestamp parser"
```

---

## Task 3: CheckmeCSVParser

**Files:**
- Create: `SleepDaddy/Services/CheckmeCSVParser.swift`
- Test: `SleepDaddyTests/CheckmeCSVParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/CheckmeCSVParserTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct CheckmeCSVParserTests {
    static let header = "Time,Oxygen Level,Pulse Rate,Motion,O2 Reminder,PR Reminder"

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    /// Builds a well-formed CSV starting at 18:02:48 Aug 03 2026 with a 2-second cadence.
    static func makeCSV(rows: [(spo2: String, pulse: String, motion: String)]) -> Data {
        var lines = [header]
        var second = 48
        var minute = 2
        var hour = 18
        for row in rows {
            let stamp = String(format: "%02d:%02d:%02d Aug 03 2026", hour, minute, second)
            lines.append("\(stamp),\(row.spo2),\(row.pulse),\(row.motion),0,0")
            second += 2
            if second >= 60 { second -= 60; minute += 1 }
            if minute >= 60 { minute -= 60; hour += 1 }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func parse(_ data: Data) throws -> VitalsSession {
        try CheckmeCSVParser(calendar: calendar).parse(data, fileName: "test.csv")
    }

    @Test func parsesAWellFormedFile() throws {
        let data = Self.makeCSV(rows: [
            ("96", "109", "86"), ("95", "108", "1"), ("94", "107", "0")
        ])
        let session = try parse(data)
        #expect(session.sampleCount == 3)
        #expect(session.spo2 == [96, 95, 94])
        #expect(session.pulse == [109, 108, 107])
        #expect(session.motion == [86, 1, 0])
        #expect(session.sourceFileNames == ["test.csv"])
    }

    @Test func missingReadingsBecomeZero() throws {
        let data = Self.makeCSV(rows: [("96", "70", "0"), ("--", "--", "2"), ("95", "69", "0")])
        let session = try parse(data)
        #expect(session.spo2 == [96, 0, 95])
        #expect(session.pulse == [70, 0, 69])
        #expect(session.spo2Value(at: 1) == nil)
        // Motion keeps recording through a dropout.
        #expect(session.motion == [0, 2, 0])
    }

    @Test func toleratesCarriageReturnsAndATrailingNewline() throws {
        var text = Self.header + "\r\n"
        text += "18:02:48 Aug 03 2026,96,70,0,0,0\r\n"
        text += "18:02:50 Aug 03 2026,95,69,1,0,0\r\n"
        let session = try parse(Data(text.utf8))
        #expect(session.sampleCount == 2)
        #expect(session.spo2 == [96, 95])
    }

    @Test func rejectsAnUnrecognisedHeader() {
        let data = Data("Time,SpO2,HR\n18:02:48 Aug 03 2026,96,70".utf8)
        #expect(throws: VitalsImportError.self) { try parse(data) }
    }

    @Test func rejectsAnEmptyFile() {
        #expect(throws: VitalsImportError.self) { try parse(Data()) }
    }

    @Test func rejectsAHeaderOnlyFile() {
        #expect(throws: VitalsImportError.self) { try parse(Data(Self.header.utf8)) }
    }

    @Test func rejectsAnUnparseableFirstTimestamp() {
        let text = Self.header + "\nnot-a-date,96,70,0,0,0\n18:02:50 Aug 03 2026,95,69,0,0,0"
        #expect(throws: VitalsImportError.self) { try parse(Data(text.utf8)) }
    }

    @Test func rejectsACadenceViolation() {
        // Last row lands 4 s after the first, but two samples imply 2 s.
        let text = Self.header
            + "\n18:02:48 Aug 03 2026,96,70,0,0,0"
            + "\n18:02:52 Aug 03 2026,95,69,0,0,0"
        #expect(throws: VitalsImportError.self) { try parse(Data(text.utf8)) }
    }

    @Test func parsesTheFullEighteenThousandRowSessionCap() throws {
        let rows = Array(repeating: ("95", "60", "0"), count: 18_000)
        let session = try parse(Self.makeCSV(rows: rows))
        #expect(session.sampleCount == 18_000)
        // 18,000 samples at 2 s spans 9 h 59 m 58 s.
        #expect(session.endDate.timeIntervalSince(session.startDate) == 35_998)
    }

    /// Guards the DateFormatter regression. A full file must parse fast enough that a
    /// night change stays interactive. The budget is deliberately loose — a
    /// per-row DateFormatter would take roughly a second and blow it by 5x.
    @Test func parsesAFullFileWellInsideTheInteractiveBudget() throws {
        let data = Self.makeCSV(rows: Array(repeating: ("95", "60", "3"), count: 18_000))
        let started = Date()
        _ = try parse(data)
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 0.2, "parse took \(elapsed)s — check for per-row DateFormatter use")
    }
}
```

- [ ] **Step 2: Write the implementation**

Create `SleepDaddy/Services/CheckmeCSVParser.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/CheckmeCSVParserTests
```

Expected: 10 tests pass, including the performance guard.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Services/CheckmeCSVParser.swift SleepDaddyTests/CheckmeCSVParserTests.swift
git commit -m "feat: add Checkme CSV parser with byte scanning"
```

---

## Task 4: VitalsSessionStitcher

**Files:**
- Create: `SleepDaddy/Services/VitalsSessionStitcher.swift`
- Test: `SleepDaddyTests/VitalsSessionStitcherTests.swift`

The device caps a session at 18,000 samples (10 hours) and opens a new file. The reference export's two files are 4 seconds apart — one continuous night.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/VitalsSessionStitcherTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct VitalsSessionStitcherTests {
    private func session(id: String, start: Date, count: Int, spo2: UInt8 = 95) -> VitalsSession {
        VitalsSession(
            id: id,
            startDate: start,
            spo2: Array(repeating: spo2, count: count),
            pulse: Array(repeating: UInt8(60), count: count),
            motion: Array(repeating: UInt8(0), count: count),
            sourceFileNames: [id]
        )
    }

    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    @Test func joinsTheReferenceFourSecondGap() {
        // Mirrors the real export: 18,000 samples then a resume 4 s later.
        let first = session(id: "a", start: epoch, count: 18_000)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(4), count: 100)

        let result = VitalsSessionStitcher().stitch([first, second])

        #expect(result.count == 1)
        #expect(result[0].sampleCount == 18_100)
        #expect(result[0].sourceFileNames == ["a", "b"])
        #expect(result[0].startDate == epoch)
    }

    @Test func aFortyMinuteGapStaysTwoSessions() {
        let first = session(id: "a", start: epoch, count: 100)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(40 * 60), count: 100)

        let result = VitalsSessionStitcher().stitch([first, second])

        #expect(result.count == 2)
    }

    @Test func joinsAThreeFileChain() {
        let first = session(id: "a", start: epoch, count: 50)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(2), count: 50)
        let third = session(id: "c", start: second.endDate.addingTimeInterval(2), count: 50)

        let result = VitalsSessionStitcher().stitch([third, first, second])

        #expect(result.count == 1)
        #expect(result[0].sampleCount == 150)
        #expect(result[0].sourceFileNames == ["a", "b", "c"])
    }

    @Test func sortsOutOfOrderInput() {
        let first = session(id: "a", start: epoch, count: 50)
        let later = session(id: "z", start: epoch.addingTimeInterval(86_400), count: 50)

        let result = VitalsSessionStitcher().stitch([later, first])

        #expect(result.count == 2)
        #expect(result[0].id == first.id)
        #expect(result[1].id == later.id)
    }

    @Test func padsTheGapSoSampleIndicesStayAlignedToTheCadence() {
        // A 4 s gap is one missing sample slot. Concatenating without padding would
        // shift every later sample 2 s early and silently misalign the whole tail.
        let first = session(id: "a", start: epoch, count: 10, spo2: 95)
        let second = session(id: "b", start: first.endDate.addingTimeInterval(4), count: 10, spo2: 88)

        let result = VitalsSessionStitcher().stitch([first, second])[0]

        #expect(result.sampleCount == 21)
        #expect(result.spo2Value(at: 10) == nil)   // the padded slot reads as a gap
        #expect(result.spo2Value(at: 11) == 88)
        #expect(result.date(at: 11) == second.startDate)
    }

    @Test func emptyInputProducesNoSessions() {
        #expect(VitalsSessionStitcher().stitch([]).isEmpty)
    }

    @Test func aSingleSessionPassesThroughUnchanged() {
        let only = session(id: "a", start: epoch, count: 10)
        let result = VitalsSessionStitcher().stitch([only])
        #expect(result.count == 1)
        #expect(result[0].sampleCount == 10)
    }
}
```

- [ ] **Step 2: Write the implementation**

Create `SleepDaddy/Services/VitalsSessionStitcher.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/VitalsSessionStitcherTests
```

Expected: 7 tests pass.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Services/VitalsSessionStitcher.swift SleepDaddyTests/VitalsSessionStitcherTests.swift
git commit -m "feat: stitch device-split recordings at load time"
```

---

## Task 5: VitalsEnvelope and VitalsEnvelopeBuilder

**Files:**
- Create: `SleepDaddy/Models/VitalsEnvelope.swift`
- Create: `SleepDaddy/Services/VitalsEnvelopeBuilder.swift`
- Test: `SleepDaddyTests/VitalsEnvelopeBuilderTests.swift`

**This is the critical suite.** Roughly 17 samples share each pixel column at full-night zoom. Averaging them erases the worst events: the reference night's 38-second dip to 73% averages against surrounding 95% readings and renders near 91%. Keeping both extremes per column costs the same and draws 73% at 73%.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/VitalsEnvelopeBuilderTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct VitalsEnvelopeBuilderTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func session(spo2: [UInt8], pulse: [UInt8]? = nil) -> VitalsSession {
        VitalsSession(
            id: "t",
            startDate: epoch,
            spo2: spo2,
            pulse: pulse ?? Array(repeating: UInt8(60), count: spo2.count),
            motion: Array(repeating: UInt8(0), count: spo2.count),
            sourceFileNames: []
        )
    }

    private func fullViewport(_ session: VitalsSession) -> TimelineViewport {
        TimelineViewport(start: session.startDate, end: session.endDate)
    }

    /// A 22,000-sample night with one brief severe dip — the shape that matters.
    private func nightWithOneDip(nadir: UInt8 = 73) -> VitalsSession {
        var values = [UInt8](repeating: 95, count: 22_000)
        for index in 11_000..<11_019 { values[index] = nadir }
        return session(spo2: values)
    }

    @Test func aSingleSevereDipSurvivesReductionToOneHundredColumns() {
        let session = nightWithOneDip()
        let envelope = VitalsEnvelopeBuilder().build(
            session: session, viewport: fullViewport(session), pixelWidth: 100
        )
        let lowest = envelope.columns.compactMap(\.spo2Min).min()
        #expect(lowest == 73)
    }

    @Test func aSingleSevereDipSurvivesReductionToTenColumns() {
        let session = nightWithOneDip()
        let envelope = VitalsEnvelopeBuilder().build(
            session: session, viewport: fullViewport(session), pixelWidth: 10
        )
        #expect(envelope.columns.compactMap(\.spo2Min).min() == 73)
    }

    @Test func aSingleSevereDipSurvivesReductionToOneColumn() {
        let session = nightWithOneDip()
        let envelope = VitalsEnvelopeBuilder().build(
            session: session, viewport: fullViewport(session), pixelWidth: 1
        )
        #expect(envelope.columns.count == 1)
        #expect(envelope.columns[0].spo2Min == 73)
        #expect(envelope.columns[0].spo2Max == 95)
    }

    @Test func theMaximumSurvivesTheSameReduction() {
        var values = [UInt8](repeating: 90, count: 5_000)
        values[2_500] = 99
        let built = VitalsEnvelopeBuilder().build(
            session: session(spo2: values),
            viewport: fullViewport(session(spo2: values)),
            pixelWidth: 20
        )
        #expect(built.columns.compactMap(\.spo2Max).max() == 99)
    }

    @Test func missingReadingsProduceAnEmptyColumnRatherThanABridge() {
        // All-missing middle third must not be spanned by the neighbours.
        var values = [UInt8](repeating: 95, count: 300)
        for index in 100..<200 { values[index] = 0 }
        let subject = session(spo2: values)
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: fullViewport(subject), pixelWidth: 3
        )
        #expect(envelope.columns[0].spo2Min == 95)
        #expect(envelope.columns[1].spo2Min == nil)
        #expect(envelope.columns[1].spo2Max == nil)
        #expect(envelope.columns[2].spo2Min == 95)
    }

    @Test func pulseIsEnvelopedIndependentlyOfSpO2() {
        let subject = session(spo2: [95, 95, 95, 95], pulse: [40, 80, 50, 70])
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: fullViewport(subject), pixelWidth: 1
        )
        #expect(envelope.columns[0].pulseMin == 40)
        #expect(envelope.columns[0].pulseMax == 80)
    }

    @Test func aViewportOutsideTheRecordingProducesEmptyColumns() {
        let subject = session(spo2: [95, 95, 95])
        let far = TimelineViewport(
            start: epoch.addingTimeInterval(86_400),
            end: epoch.addingTimeInterval(90_000)
        )
        let envelope = VitalsEnvelopeBuilder().build(session: subject, viewport: far, pixelWidth: 5)
        #expect(envelope.columns.count == 5)
        #expect(envelope.columns.allSatisfy { $0.spo2Min == nil })
    }

    @Test func aViewportOverlappingOnlyPartOfTheRecordingClipsCleanly() {
        let subject = session(spo2: [90, 91, 92, 93])
        // Starts one full recording-length before the data.
        let viewport = TimelineViewport(
            start: epoch.addingTimeInterval(-6),
            end: epoch.addingTimeInterval(2)
        )
        let envelope = VitalsEnvelopeBuilder().build(session: subject, viewport: viewport, pixelWidth: 4)
        #expect(envelope.columns.count == 4)
        #expect(envelope.columns.compactMap(\.spo2Min).min() == 90)
    }

    @Test func zeroOrNegativePixelWidthProducesNoColumnsRatherThanCrashing() {
        let subject = session(spo2: [95, 95])
        #expect(VitalsEnvelopeBuilder().build(session: subject, viewport: fullViewport(subject), pixelWidth: 0).columns.isEmpty)
        #expect(VitalsEnvelopeBuilder().build(session: subject, viewport: fullViewport(subject), pixelWidth: -3).columns.isEmpty)
    }

    @Test func anEmptySessionProducesEmptyColumnsRatherThanCrashing() {
        let empty = session(spo2: [])
        let viewport = TimelineViewport(start: epoch, end: epoch.addingTimeInterval(60))
        let envelope = VitalsEnvelopeBuilder().build(session: empty, viewport: viewport, pixelWidth: 4)
        #expect(envelope.columns.count == 4)
        #expect(envelope.columns.allSatisfy { $0.isEmpty })
    }

    @Test func zoomedPastOneToOneEveryColumnStillCarriesASample() {
        // 4 samples across 40 columns: each sample is held for its two seconds.
        let subject = session(spo2: [90, 91, 92, 93])
        let envelope = VitalsEnvelopeBuilder().build(
            session: subject, viewport: fullViewport(subject), pixelWidth: 40
        )
        #expect(envelope.columns.allSatisfy { !$0.isEmpty })
        #expect(envelope.columns.compactMap(\.spo2Min).min() == 90)
        #expect(envelope.columns.compactMap(\.spo2Max).max() == 93)
    }
}
```

- [ ] **Step 2: Write the model**

Create `SleepDaddy/Models/VitalsEnvelope.swift`:

```swift
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
```

- [ ] **Step 3: Write the builder**

Create `SleepDaddy/Services/VitalsEnvelopeBuilder.swift`:

```swift
import Foundation

/// Reduces a full sample array to one min/max pair per pixel column.
///
/// **Both extremes are kept.** Averaging a column would erase brief severe events: a
/// 38-second dip to 73% averaged against surrounding 95% readings renders near 91% and
/// vanishes. Keeping the minimum costs nothing and draws 73% at 73%, so zooming out
/// narrows an event's width but never softens its depth.
///
/// Runs per frame against the complete session. At roughly 22,000 samples a full scan is
/// inexpensive, so there is no resolution pyramid and no cache. If a future multi-night
/// view makes the cost real, a cache goes behind this type without touching callers.
public struct VitalsEnvelopeBuilder: Sendable {
    public init() {}

    public func build(
        session: VitalsSession,
        viewport: TimelineViewport,
        pixelWidth: Int
    ) -> VitalsEnvelope {
        guard pixelWidth > 0 else { return VitalsEnvelope(columns: []) }

        let sampleCount = session.sampleCount
        guard sampleCount > 0 else {
            return VitalsEnvelope(columns: Array(repeating: .empty, count: pixelWidth))
        }

        var columns: [VitalsEnvelope.Column] = []
        columns.reserveCapacity(pixelWidth)

        let viewportSeconds = max(viewport.duration, .leastNonzeroMagnitude)

        for column in 0..<pixelWidth {
            // The time slice this column covers, converted to sample indices.
            let fromRatio = Double(column) / Double(pixelWidth)
            let toRatio = Double(column + 1) / Double(pixelWidth)
            let columnStart = viewport.start.addingTimeInterval(viewportSeconds * fromRatio)
            let columnEnd = viewport.start.addingTimeInterval(viewportSeconds * toRatio)

            var lower = session.index(for: columnStart)
            var upper = session.index(for: columnEnd)

            // Zoomed past 1:1 the slice can be narrower than one sample. Hold the
            // containing sample so the lane draws a step rather than a gap.
            if upper <= lower { upper = lower + 1 }

            lower = max(0, lower)
            upper = min(sampleCount, upper)

            guard lower < upper else {
                columns.append(.empty)
                continue
            }

            var spo2Min: UInt8?
            var spo2Max: UInt8?
            var pulseMin: UInt8?
            var pulseMax: UInt8?

            for index in lower..<upper {
                let oxygen = session.spo2[index]
                if oxygen != 0 {
                    spo2Min = min(spo2Min ?? oxygen, oxygen)
                    spo2Max = max(spo2Max ?? oxygen, oxygen)
                }
                let rate = session.pulse[index]
                if rate != 0 {
                    pulseMin = min(pulseMin ?? rate, rate)
                    pulseMax = max(pulseMax ?? rate, rate)
                }
            }

            columns.append(VitalsEnvelope.Column(
                spo2Min: spo2Min, spo2Max: spo2Max,
                pulseMin: pulseMin, pulseMax: pulseMax
            ))
        }

        return VitalsEnvelope(columns: columns)
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/VitalsEnvelopeBuilderTests
```

Expected: 11 tests pass. If any dip-survival test fails, **stop** — the feature's core guarantee is broken.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Models/VitalsEnvelope.swift SleepDaddy/Services/VitalsEnvelopeBuilder.swift SleepDaddyTests/VitalsEnvelopeBuilderTests.swift
git commit -m "feat: add min/max envelope builder preserving severe dips"
```

---

## Task 6: VitalsColorZone

**Files:**
- Create: `SleepDaddy/Models/VitalsColorZone.swift`
- Test: `SleepDaddyTests/VitalsColorZoneTests.swift`

Colours were validated, not chosen by eye. Green is excluded: status green against status orange measures ΔE 5.6 under protanopia against a target of 8, so roughly 1 in 12 men would see the normal and concerning zones as nearly the same colour. Substituting the series blue takes the worst pair to ΔE 24.4. Three zones rather than four because status warning against status serious measures ΔE 13.6 under *normal* vision, below the floor of 15.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/VitalsColorZoneTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct VitalsColorZoneTests {
    @Test func boundariesAreInclusiveAtTheirLowerEdge() {
        #expect(VitalsColorZone.zone(forSpO2: 91) == .normal)
        #expect(VitalsColorZone.zone(forSpO2: 90) == .normal)
        #expect(VitalsColorZone.zone(forSpO2: 89) == .warning)
        #expect(VitalsColorZone.zone(forSpO2: 86) == .warning)
        #expect(VitalsColorZone.zone(forSpO2: 85) == .warning)
        #expect(VitalsColorZone.zone(forSpO2: 84) == .critical)
    }

    @Test func extremesLandInTheExpectedZones() {
        #expect(VitalsColorZone.zone(forSpO2: 100) == .normal)
        #expect(VitalsColorZone.zone(forSpO2: 73) == .critical)
        #expect(VitalsColorZone.zone(forSpO2: 0) == .critical)
    }

    @Test func legendLabelsStateNumbersRatherThanVerdicts() {
        // The threshold is a display choice; a word like "Critical" would be a verdict,
        // and the app does not characterise what it draws.
        #expect(VitalsColorZone.normal.legendLabel == "90% and above")
        #expect(VitalsColorZone.warning.legendLabel == "85–90%")
        #expect(VitalsColorZone.critical.legendLabel == "Below 85%")

        for zone in VitalsColorZone.allCases {
            let label = zone.legendLabel.lowercased()
            for verdict in ["critical", "danger", "severe", "concerning", "normal", "bad", "good"] {
                #expect(!label.contains(verdict), "\(zone) label leaks a verdict: \(zone.legendLabel)")
            }
        }
    }

    @Test func zonesDescendInValueOrder() {
        #expect(VitalsColorZone.allCases == [.normal, .warning, .critical])
    }

    @Test func eachZoneHasADistinctUpperBound() {
        #expect(VitalsColorZone.warningLowerBound == 85)
        #expect(VitalsColorZone.normalLowerBound == 90)
    }

    @Test func zoneRangesTileTheScaleWithoutOverlapOrGap() {
        for value in UInt8(0)...UInt8(100) {
            let matching = VitalsColorZone.allCases.filter { $0.contains(spo2: value) }
            #expect(matching.count == 1, "value \(value) matched \(matching.count) zones")
            #expect(matching[0] == VitalsColorZone.zone(forSpO2: value))
        }
    }
}
```

- [ ] **Step 2: Write the implementation**

Create `SleepDaddy/Models/VitalsColorZone.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/VitalsColorZoneTests
```

Expected: 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Models/VitalsColorZone.swift SleepDaddyTests/VitalsColorZoneTests.swift
git commit -m "feat: add validated three-zone SpO2 colour bands"
```

---

## Task 7: DesaturationEvent and DesaturationDetector

**Files:**
- Create: `SleepDaddy/Models/DesaturationEvent.swift`
- Create: `SleepDaddy/Services/DesaturationDetector.swift`
- Test: `SleepDaddyTests/DesaturationDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/DesaturationDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct DesaturationDetectorTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func session(_ spo2: [UInt8]) -> VitalsSession {
        VitalsSession(
            id: "t", startDate: epoch, spo2: spo2,
            pulse: Array(repeating: UInt8(60), count: spo2.count),
            motion: Array(repeating: UInt8(0), count: spo2.count),
            sourceFileNames: []
        )
    }

    /// 60 samples of baseline, then a dip, then recovery.
    private func dipSession(baseline: UInt8, nadir: UInt8, dipLength: Int) -> VitalsSession {
        var values = [UInt8](repeating: baseline, count: 60)
        values += [UInt8](repeating: nadir, count: dipLength)
        values += [UInt8](repeating: baseline, count: 60)
        return session(values)
    }

    @Test func detectsASingleFourPercentDrop() {
        let events = DesaturationDetector().events(in: dipSession(baseline: 95, nadir: 91, dipLength: 10))
        #expect(events.count == 1)
        #expect(events[0].nadir == 91)
        #expect(events[0].baseline == 95)
        #expect(events[0].dropAmount == 4)
    }

    @Test func ignoresADropSmallerThanTheThreshold() {
        let events = DesaturationDetector().events(in: dipSession(baseline: 95, nadir: 92, dipLength: 10))
        #expect(events.isEmpty)
    }

    @Test func recordsTheDeepestPointNotTheFirst() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [90, 84, 79, 84, 90]
        values += [UInt8](repeating: 96, count: 60)
        let events = DesaturationDetector().events(in: session(values))
        #expect(events.count == 1)
        #expect(events[0].nadir == 79)
    }

    @Test func detectsTwoSeparatedEvents() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 88, count: 10)
        values += [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 87, count: 10)
        values += [UInt8](repeating: 96, count: 60)
        #expect(DesaturationDetector().events(in: session(values)).count == 2)
    }

    @Test func missingReadingsProduceNoEvents() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 0, count: 30)   // sensor off the finger
        values += [UInt8](repeating: 96, count: 60)
        #expect(DesaturationDetector().events(in: session(values)).isEmpty)
    }

    @Test func aFlatRecordingProducesNoEvents() {
        #expect(DesaturationDetector().events(in: session(Array(repeating: 96, count: 500))).isEmpty)
    }

    @Test func aRecordingShorterThanTheBaselineWindowProducesNoEvents() {
        #expect(DesaturationDetector().events(in: session(Array(repeating: 96, count: 10))).isEmpty)
    }

    @Test func anEmptySessionProducesNoEvents() {
        #expect(DesaturationDetector().events(in: session([])).isEmpty)
    }

    @Test func eventDatesMapBackOntoTheSession() {
        let subject = dipSession(baseline: 95, nadir: 88, dipLength: 10)
        let events = DesaturationDetector().events(in: subject)
        #expect(events.count == 1)
        #expect(events[0].startDate >= subject.startDate)
        #expect(events[0].endDate <= subject.endDate)
        #expect(events[0].endDate > events[0].startDate)
    }

    @Test func railEventsAreThoseReachingBelowNinety() {
        var values = [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 91, count: 10)   // a 5% drop, but nadir stays >= 90
        values += [UInt8](repeating: 96, count: 60)
        values += [UInt8](repeating: 86, count: 10)   // reaches below 90
        values += [UInt8](repeating: 96, count: 60)

        let all = DesaturationDetector().events(in: session(values))
        #expect(all.count == 2)

        let rail = all.filter(\.reachesRailThreshold)
        #expect(rail.count == 1)
        #expect(rail[0].nadir == 86)
    }
}
```

- [ ] **Step 2: Write the model**

Create `SleepDaddy/Models/DesaturationEvent.swift`:

```swift
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
```

- [ ] **Step 3: Write the detector**

Create `SleepDaddy/Services/DesaturationDetector.swift`:

```swift
import Foundation

/// Finds oxygen desaturations using a rolling baseline.
///
/// Conventional signal-processing parameters for making events visible on a chart. This
/// is **not** a clinical scoring implementation.
public struct DesaturationDetector: Sendable {
    /// A reading this far below the rolling baseline opens an event.
    public static let dropThreshold: Int = 4

    /// The baseline is the highest reading over this preceding window.
    public static let baselineWindow: TimeInterval = 120

    /// Events reaching below this are marked on the rail. Matches the first colour zone.
    public static let railNadirThreshold: UInt8 = 90

    private var baselineSampleCount: Int {
        Int(Self.baselineWindow / VitalsSession.sampleInterval)
    }

    public init() {}

    public func events(in session: VitalsSession) -> [DesaturationEvent] {
        let window = baselineSampleCount
        let count = session.sampleCount
        guard count > window else { return [] }

        var events: [DesaturationEvent] = []
        var index = window

        while index < count {
            guard let value = session.spo2Value(at: index),
                  let baseline = Self.baseline(in: session, endingBefore: index, window: window),
                  Int(baseline) - Int(value) >= Self.dropThreshold
            else {
                index += 1
                continue
            }

            // Walk to recovery, tracking the deepest point.
            var nadir = value
            var cursor = index
            while cursor < count,
                  let current = session.spo2Value(at: cursor),
                  Int(baseline) - Int(current) >= Self.dropThreshold {
                nadir = min(nadir, current)
                cursor += 1
            }

            events.append(DesaturationEvent(
                startDate: session.date(at: index),
                endDate: session.date(at: cursor),
                nadir: nadir,
                baseline: baseline
            ))

            index = cursor + 1
        }

        return events
    }

    /// Highest valid reading in the `window` samples before `index`. `nil` when the whole
    /// window is missing, so a sensor dropout cannot manufacture an event.
    private static func baseline(in session: VitalsSession, endingBefore index: Int, window: Int) -> UInt8? {
        var best: UInt8?
        for offset in max(0, index - window)..<index {
            if let value = session.spo2Value(at: offset) {
                best = max(best ?? value, value)
            }
        }
        return best
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/DesaturationDetectorTests
```

Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Models/DesaturationEvent.swift SleepDaddy/Services/DesaturationDetector.swift SleepDaddyTests/DesaturationDetectorTests.swift
git commit -m "feat: detect desaturation events with a rolling baseline"
```

---

## Task 8: VitalsLaneGeometry

**Files:**
- Create: `SleepDaddy/Layout/VitalsLaneGeometry.swift`
- Test: `SleepDaddyTests/VitalsLaneGeometryTests.swift`

x comes from `SleepTimelineGeometry` unchanged — that is what keeps the lanes locked to the stage plot through pinch and pan. This type handles **only** value → y, which the existing geometry has no concept of.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/VitalsLaneGeometryTests.swift`:

```swift
import Testing
import Foundation
import CoreGraphics
@testable import SleepDaddy

struct VitalsLaneGeometryTests {
    @Test func theMaximumSitsAtTheTopAndTheMinimumAtTheBottom() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 100)
        #expect(geometry.yPosition(for: 100) == 0)
        #expect(geometry.yPosition(for: 70) == 100)
    }

    @Test func themidpointLandsHalfway() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 100)
        #expect(geometry.yPosition(for: 85) == 50)
    }

    @Test func valuesBeyondTheRangeClampToTheLaneEdges() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 100)
        #expect(geometry.yPosition(for: 120) == 0)
        #expect(geometry.yPosition(for: 10) == 100)
    }

    @Test func aZeroHeightLaneDoesNotDivideByZero() {
        let geometry = VitalsLaneGeometry(minValue: 70, maxValue: 100, laneHeight: 0)
        #expect(geometry.yPosition(for: 85).isFinite)
    }

    @Test func aDegenerateRangeDoesNotDivideByZero() {
        let geometry = VitalsLaneGeometry(minValue: 90, maxValue: 90, laneHeight: 100)
        #expect(geometry.yPosition(for: 90).isFinite)
    }

    @Test func theStandardScalesMatchTheDesign() {
        #expect(VitalsLaneGeometry.spo2(laneHeight: 60).minValue == 70)
        #expect(VitalsLaneGeometry.spo2(laneHeight: 60).maxValue == 100)
        #expect(VitalsLaneGeometry.pulse(laneHeight: 60).minValue == 30)
        #expect(VitalsLaneGeometry.pulse(laneHeight: 60).maxValue == 110)
    }

    /// The lanes and the stage plot must agree on x for the same viewport, or pinch and
    /// pan would visibly desynchronise them.
    @Test func vitalsAndSleepAgreeOnXForTheSameViewport() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let viewport = TimelineViewport(start: start, end: start.addingTimeInterval(3600))
        let sleep = SleepTimelineGeometry(
            totalStart: start, totalEnd: start.addingTimeInterval(7200),
            viewport: viewport, canvasWidth: 400, canvasHeight: 300
        )
        let lanes = SleepTimelineGeometry(
            totalStart: start, totalEnd: start.addingTimeInterval(7200),
            viewport: viewport, canvasWidth: 400, canvasHeight: 80
        )
        for minutes in stride(from: 0, through: 60, by: 10) {
            let moment = start.addingTimeInterval(Double(minutes) * 60)
            #expect(sleep.xPosition(for: moment) == lanes.xPosition(for: moment))
        }
    }
}
```

- [ ] **Step 2: Write the implementation**

Create `SleepDaddy/Layout/VitalsLaneGeometry.swift`:

```swift
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

    public func yPosition(for value: UInt8) -> CGFloat {
        yPosition(for: Double(value))
    }
}
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/VitalsLaneGeometryTests
```

Expected: 7 tests pass.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/Layout/VitalsLaneGeometry.swift SleepDaddyTests/VitalsLaneGeometryTests.swift
git commit -m "feat: add vitals lane value-to-y geometry"
```

---

## Task 9: VitalsStore protocol and FileVitalsStore

**Files:**
- Create: `SleepDaddy/Services/VitalsStore.swift`
- Create: `SleepDaddy/Services/FileVitalsStore.swift`
- Test: `SleepDaddyTests/FileVitalsStoreTests.swift`

The imported CSV is stored losslessly and is the source of truth. No decoded format is persisted, so changing `VitalsSession` needs no migration and a parser fix repairs every recording already imported.

**A note on compression level.** The design document records zlib level 6 from a benchmark. Apple's `NSData.compressed(using:)` exposes **no level parameter** — the Compression framework picks its own. Use `.zlib` and accept it; measured output lands close to the level-6 figure. Do not add a third-party zlib to chase the exact level.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/FileVitalsStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct FileVitalsStoreTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    /// Each test gets its own directory so runs cannot contaminate each other.
    private func makeStore() throws -> (FileVitalsStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitals-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try FileVitalsStore(directory: directory, calendar: calendar)
        return (store, directory)
    }

    private func sampleCSV(rows: Int, startHour: Int = 18) -> Data {
        var lines = [CheckmeCSVParser.expectedHeader]
        var second = 0, minute = 0, hour = startHour
        for _ in 0..<rows {
            lines.append(String(format: "%02d:%02d:%02d Aug 03 2026,95,60,0,0,0", hour, minute, second))
            second += 2
            if second >= 60 { second -= 60; minute += 1 }
            if minute >= 60 { minute -= 60; hour += 1 }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    @Test func importThenLoadRoundTripsTheSamples() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptor = try store.importRecording(sampleCSV(rows: 100), originalName: "x.csv")
        let session = try store.loadSession(for: descriptor)

        #expect(session.sampleCount == 100)
        #expect(session.spo2.allSatisfy { $0 == 95 })
    }

    @Test func storedBytesDecompressToTheImportedFileExactly() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sampleCSV(rows: 50)
        let descriptor = try store.importRecording(original, originalName: "x.csv")

        #expect(try store.originalCSV(for: descriptor) == original)
    }

    @Test func compressionActuallyShrinksTheFile() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sampleCSV(rows: 2_000)
        let descriptor = try store.importRecording(original, originalName: "x.csv")
        let onDisk = try Data(contentsOf: descriptor.url)

        #expect(onDisk.count < original.count / 3)
    }

    @Test func theFileNameCarriesTheSpanSoLookupNeedsNoDecompression() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptor = try store.importRecording(sampleCSV(rows: 100), originalName: "x.csv")
        let recovered = try store.allDescriptors()

        #expect(recovered.count == 1)
        #expect(recovered[0].start == descriptor.start)
        #expect(recovered[0].end == descriptor.end)
    }

    @Test func reimportingTheSameRecordingIsANoOp() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let data = sampleCSV(rows: 100)
        _ = try store.importRecording(data, originalName: "x.csv")
        _ = try store.importRecording(data, originalName: "copy-of-x.csv")

        #expect(try store.allDescriptors().count == 1)
    }

    @Test func aMalformedFileIsRejectedAndNothingIsWritten() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: VitalsImportError.self) {
            try store.importRecording(Data("nope,not,a,csv".utf8), originalName: "bad.csv")
        }
        #expect(try store.allDescriptors().isEmpty)
    }

    @Test func descriptorsOverlappingANightAreFound() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptor = try store.importRecording(sampleCSV(rows: 1_000), originalName: "x.csv")
        let night = DateInterval(
            start: descriptor.start.addingTimeInterval(-3_600),
            end: descriptor.end.addingTimeInterval(3_600)
        )

        #expect(try store.descriptors(overlapping: night).count == 1)

        let elsewhere = DateInterval(
            start: descriptor.end.addingTimeInterval(86_400),
            end: descriptor.end.addingTimeInterval(90_000)
        )
        #expect(try store.descriptors(overlapping: elsewhere).isEmpty)
    }

    @Test func anEmptyStoreReturnsNoDescriptors() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try store.allDescriptors().isEmpty)
    }

    @Test func unrelatedFilesInTheDirectoryAreIgnored() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try store.importRecording(sampleCSV(rows: 100), originalName: "x.csv")
        try Data("junk".utf8).write(to: directory.appendingPathComponent("README.txt"))
        try Data("junk".utf8).write(to: directory.appendingPathComponent("nonsense.csv.z"))

        #expect(try store.allDescriptors().count == 1)
    }
}
```

- [ ] **Step 2: Write the protocol**

Create `SleepDaddy/Services/VitalsStore.swift`:

```swift
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
```

- [ ] **Step 3: Write the file store**

Create `SleepDaddy/Services/FileVitalsStore.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData -only-testing:SleepDaddyTests/FileVitalsStoreTests
```

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Services/VitalsStore.swift SleepDaddy/Services/FileVitalsStore.swift SleepDaddyTests/FileVitalsStoreTests.swift
git commit -m "feat: store imported CSV compressed and losslessly"
```

---

## Task 10: Data-defined timeline extent

**Files:**
- Modify: `SleepDaddy/Models/AssembledNight.swift`
- Modify: `SleepDaddyTests/NightAssemblerTests.swift`
- Test: `SleepDaddyTests/AssembledNightExtentTests.swift`

`timelineStart`/`timelineEnd` currently floor to the configured core window, so a night is pannable across 19:00–07:00 even when sleep occupied only part of it. A recording beginning at 18:02 would fall outside the timeline and the pre-sleep waking baseline would be lost.

**This is a deliberate behaviour change for every night, including those with no vitals.** The core window keeps its other job — seeding which intervals belong to a night in `NightAssembler` — unchanged. Only the extent job is removed.

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/AssembledNightExtentTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

struct AssembledNightExtentTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    private func night(
        coreStart: TimeInterval, coreEnd: TimeInterval,
        detectedStart: TimeInterval, detectedEnd: TimeInterval,
        vitals: DateInterval? = nil
    ) -> AssembledNight {
        AssembledNight(
            date: epoch,
            coreWindowStart: epoch.addingTimeInterval(coreStart),
            coreWindowEnd: epoch.addingTimeInterval(coreEnd),
            detectedStart: epoch.addingTimeInterval(detectedStart),
            detectedEnd: epoch.addingTimeInterval(detectedEnd),
            rawIntervals: [], primaryLaneIntervals: [], displayLaneIntervals: [],
            conflicts: [], summary: .empty, hasSleepData: true,
            vitalsExtent: vitals
        )
    }

    @Test func withoutVitalsTheExtentFollowsTheDetectedSpanNotTheCoreWindow() {
        // Core window 0–43200; sleep only occupied 14400–28800.
        let subject = night(coreStart: 0, coreEnd: 43_200, detectedStart: 14_400, detectedEnd: 28_800)

        #expect(subject.timelineStart == subject.preferredViewportStart)
        #expect(subject.timelineEnd == subject.preferredViewportEnd)
        // The old behaviour floored to the core window; it no longer does.
        #expect(subject.timelineStart > subject.coreWindowStart)
    }

    @Test func vitalsStartingEarlierWidenTheExtent() {
        let vitalsStart = epoch.addingTimeInterval(10_000)
        let subject = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(start: vitalsStart, end: epoch.addingTimeInterval(30_000))
        )

        #expect(subject.timelineStart == vitalsStart)
        #expect(subject.timelineEnd == epoch.addingTimeInterval(30_000))
    }

    @Test func vitalsInsideTheSleepSpanDoNotNarrowTheExtent() {
        let subject = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(
                start: epoch.addingTimeInterval(20_000),
                end: epoch.addingTimeInterval(21_000)
            )
        )

        #expect(subject.timelineStart == subject.preferredViewportStart)
        #expect(subject.timelineEnd == subject.preferredViewportEnd)
    }

    @Test func theOpeningViewportIsUnaffectedByVitals() {
        let withoutVitals = night(coreStart: 0, coreEnd: 43_200, detectedStart: 14_400, detectedEnd: 28_800)
        let withVitals = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(start: epoch, end: epoch.addingTimeInterval(40_000))
        )

        #expect(withoutVitals.preferredViewportStart == withVitals.preferredViewportStart)
        #expect(withoutVitals.preferredViewportEnd == withVitals.preferredViewportEnd)
    }

    @Test func thePreferredViewportAlwaysFitsInsideTheExtent() {
        let subject = night(
            coreStart: 0, coreEnd: 43_200,
            detectedStart: 14_400, detectedEnd: 28_800,
            vitals: DateInterval(start: epoch, end: epoch.addingTimeInterval(40_000))
        )

        #expect(subject.timelineStart <= subject.preferredViewportStart)
        #expect(subject.timelineEnd >= subject.preferredViewportEnd)
    }

    @Test func attachingAnExtentPreservesEveryOtherField() {
        let base = night(coreStart: 0, coreEnd: 43_200, detectedStart: 14_400, detectedEnd: 28_800)
        let extent = DateInterval(start: epoch, end: epoch.addingTimeInterval(40_000))
        let attached = base.withVitalsExtent(extent)

        #expect(attached.vitalsExtent == extent)
        #expect(attached.date == base.date)
        #expect(attached.detectedStart == base.detectedStart)
        #expect(attached.detectedEnd == base.detectedEnd)
        #expect(attached.hasSleepData == base.hasSleepData)
        #expect(attached.summary == base.summary)
    }
}
```

- [ ] **Step 2: Modify AssembledNight**

In `SleepDaddy/Models/AssembledNight.swift`, add the stored property after `hasSleepData`:

```swift
    public let hasSleepData: Bool

    /// The span of pulse-oximeter data attached to this night, when any exists.
    ///
    /// Set by `NightBrowserModel` after assembly, never by `NightAssembler` — vitals have
    /// nothing to do with grouping sleep intervals, and threading a store through the
    /// assembler would join two unrelated concerns.
    public let vitalsExtent: DateInterval?
```

Replace `timelineStart` and `timelineEnd`:

```swift
    /// Full navigable timeline, defined by **data** rather than by the configured core
    /// window. The gutter-padded detected span is the floor, widened by any vitals
    /// recording that extends beyond it.
    ///
    /// The core window no longer participates. It keeps its other responsibility — seeding
    /// which intervals belong to a night in `NightAssembler` — unchanged. A night with
    /// sleep from 23:00 to 06:00 previously allowed panning back to 19:00 across empty
    /// evening; it now bounds to the data.
    public var timelineStart: Date {
        guard let vitalsExtent else { return preferredViewportStart }
        return min(preferredViewportStart, vitalsExtent.start)
    }

    public var timelineEnd: Date {
        guard let vitalsExtent else { return preferredViewportEnd }
        return max(preferredViewportEnd, vitalsExtent.end)
    }
```

Add `vitalsExtent` to the initializer, defaulted so existing call sites compile unchanged:

```swift
    public init(
        date: Date,
        coreWindowStart: Date,
        coreWindowEnd: Date,
        detectedStart: Date,
        detectedEnd: Date,
        rawIntervals: [NormalizedSleepInterval],
        primaryLaneIntervals: [NormalizedSleepInterval],
        displayLaneIntervals: [NormalizedSleepInterval],
        conflicts: [TimelineConflict],
        summary: NightSummary,
        hasSleepData: Bool,
        vitalsExtent: DateInterval? = nil
    ) {
        self.date = date
        self.coreWindowStart = coreWindowStart
        self.coreWindowEnd = coreWindowEnd
        self.detectedStart = detectedStart
        self.detectedEnd = detectedEnd
        self.rawIntervals = rawIntervals
        self.primaryLaneIntervals = primaryLaneIntervals
        self.displayLaneIntervals = displayLaneIntervals
        self.conflicts = conflicts
        self.summary = summary
        self.hasSleepData = hasSleepData
        self.vitalsExtent = vitalsExtent
    }

    /// Returns a copy carrying `extent`. Used by `NightBrowserModel` to attach vitals
    /// without `NightAssembler` knowing they exist.
    public func withVitalsExtent(_ extent: DateInterval?) -> AssembledNight {
        AssembledNight(
            date: date,
            coreWindowStart: coreWindowStart,
            coreWindowEnd: coreWindowEnd,
            detectedStart: detectedStart,
            detectedEnd: detectedEnd,
            rawIntervals: rawIntervals,
            primaryLaneIntervals: primaryLaneIntervals,
            displayLaneIntervals: displayLaneIntervals,
            conflicts: conflicts,
            summary: summary,
            hasSleepData: hasSleepData,
            vitalsExtent: extent
        )
    }
```

- [ ] **Step 3: Run the full suite to find every expectation that encoded the old floor**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: `AssembledNightExtentTests` passes. Some existing assertions in `NightAssemblerTests` and `SleepTimelineGeometryTests` will fail where they asserted `timelineStart == coreWindowStart`.

- [ ] **Step 4: Update the failing expectations**

For each failure, the correct new expectation is `preferredViewportStart` / `preferredViewportEnd` rather than the core window. Add a comment at each changed assertion:

```swift
// The timeline extent is data-defined; the core window no longer floors it.
```

Do **not** weaken an assertion to make it pass. If a test's intent was to verify core-window seeding rather than extent, keep it asserting on `coreWindowStart` directly.

- [ ] **Step 5: Re-run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: all suites pass. Verify the output lists every suite — a crashed runner can hide a skipped one.

- [ ] **Step 6: Commit**

```bash
git add SleepDaddy/Models/AssembledNight.swift SleepDaddyTests/
git commit -m "feat: define the timeline extent from data rather than the core window"
```

---

## Task 11: Rendering — rail and envelope lanes

**Files:**
- Create: `SleepDaddy/Views/DesaturationRailView.swift`
- Create: `SleepDaddy/Views/VitalsEnvelopeLane.swift`
- Create: `SleepDaddy/Views/VitalsLanesView.swift`

No pixel-snapshot tests — the lanes are verified by SwiftUI previews driven by real fixture data. Logic is already covered by Tasks 5–8.

- [ ] **Step 1: Write the rail**

Create `SleepDaddy/Views/DesaturationRailView.swift`:

```swift
import SwiftUI

/// A thin rail marking desaturation events, drawn directly beneath the stage plot so
/// clusters register before either chart is read.
public struct DesaturationRailView: View {
    let events: [DesaturationEvent]
    let geometry: SleepTimelineGeometry

    public static let railHeight: CGFloat = 6

    public init(events: [DesaturationEvent], geometry: SleepTimelineGeometry) {
        self.events = events
        self.geometry = geometry
    }

    public var body: some View {
        Canvas { context, size in
            for event in events where event.reachesRailThreshold {
                let startX = geometry.xPosition(for: event.startDate)
                let endX = geometry.xPosition(for: event.endDate)
                // A brief event can be sub-pixel; give it a floor so it stays visible.
                let width = max(2, endX - startX)
                guard endX >= 0, startX <= size.width else { continue }

                let rect = CGRect(x: startX, y: 0, width: width, height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: size.height / 2),
                    with: .color(VitalsColorZone.critical.color)
                )
            }
        }
        .frame(height: Self.railHeight)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let marked = events.filter(\.reachesRailThreshold)
        guard !marked.isEmpty else { return "No oxygen events below 90 percent" }
        let lowest = marked.map(\.nadir).min() ?? 0
        return "\(marked.count) oxygen events below 90 percent, lowest \(lowest) percent"
    }
}
```

- [ ] **Step 2: Write the envelope lane**

Create `SleepDaddy/Views/VitalsEnvelopeLane.swift`:

```swift
import SwiftUI

/// One min/max envelope lane. Used for both SpO₂ and pulse — they never share a lane,
/// because two scales on one plot is a dual-axis chart whose arbitrary scale alignment
/// invents correlations that are not in the data.
public struct VitalsEnvelopeLane: View {
    public enum Measure {
        case spo2
        case pulse
    }

    let envelope: VitalsEnvelope
    let measure: Measure
    let laneHeight: CGFloat

    public init(envelope: VitalsEnvelope, measure: Measure, laneHeight: CGFloat) {
        self.envelope = envelope
        self.measure = measure
        self.laneHeight = laneHeight
    }

    private var laneGeometry: VitalsLaneGeometry {
        switch measure {
        case .spo2: return .spo2(laneHeight: laneHeight)
        case .pulse: return .pulse(laneHeight: laneHeight)
        }
    }

    public var body: some View {
        Canvas { context, size in
            let scale = VitalsLaneGeometry(
                minValue: laneGeometry.minValue,
                maxValue: laneGeometry.maxValue,
                laneHeight: size.height
            )
            let columnWidth = size.width / CGFloat(max(1, envelope.columns.count))

            switch measure {
            case .spo2:
                drawZonedSpO2(context: context, size: size, scale: scale, columnWidth: columnWidth)
            case .pulse:
                drawPulse(context: context, size: size, scale: scale, columnWidth: columnWidth)
            }
        }
        .frame(height: laneHeight)
    }

    /// Colour follows the **value**, not the column, so a band crossing a threshold is
    /// coloured only in the part that crosses.
    private func drawZonedSpO2(
        context: GraphicsContext, size: CGSize,
        scale: VitalsLaneGeometry, columnWidth: CGFloat
    ) {
        for zone in VitalsColorZone.allCases {
            var path = Path()
            for (index, column) in envelope.columns.enumerated() {
                guard let low = column.spo2Min, let high = column.spo2Max else { continue }

                // Clip this column's span to the zone's value range.
                let zoneLow = zone.lowerBound.map { Double($0) } ?? scale.minValue
                let zoneHigh = zone.upperBound.map { Double($0) } ?? scale.maxValue
                let clippedLow = max(Double(low), zoneLow)
                let clippedHigh = min(Double(high), zoneHigh)
                guard clippedLow <= clippedHigh else { continue }

                let x = CGFloat(index) * columnWidth
                let top = scale.yPosition(for: clippedHigh)
                let bottom = scale.yPosition(for: clippedLow)
                path.addRect(CGRect(
                    x: x, y: top,
                    width: max(columnWidth, 1),
                    height: max(bottom - top, 1)
                ))
            }
            context.fill(path, with: .color(zone.color))
        }
    }

    private func drawPulse(
        context: GraphicsContext, size: CGSize,
        scale: VitalsLaneGeometry, columnWidth: CGFloat
    ) {
        var path = Path()
        for (index, column) in envelope.columns.enumerated() {
            guard let low = column.pulseMin, let high = column.pulseMax else { continue }
            let x = CGFloat(index) * columnWidth
            let top = scale.yPosition(for: high)
            let bottom = scale.yPosition(for: low)
            path.addRect(CGRect(
                x: x, y: top,
                width: max(columnWidth, 1),
                height: max(bottom - top, 1)
            ))
        }
        context.fill(path, with: .color(VitalsColorZone.pulseColor.opacity(0.65)))
    }
}
```

- [ ] **Step 3: Write the composed lanes view**

Create `SleepDaddy/Views/VitalsLanesView.swift`:

```swift
import SwiftUI

/// Rail plus the two envelope lanes, beneath the stage plot and sharing its time axis.
///
/// Builds its own `SleepTimelineGeometry` from the same night and viewport as the stage
/// plot, and reserves the same leading label column, so both stay aligned. Because the
/// viewport lives in `NightBrowserModel`, pinch and pan on the canvas re-render these
/// lanes automatically — there is nothing to synchronise.
public struct VitalsLanesView: View {
    let session: VitalsSession
    let events: [DesaturationEvent]
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date

    /// Matches `SleepTimelineCanvas`'s stage-label column so the x axes line up.
    private static let labelWidth: CGFloat = 68
    private static let spo2LaneHeight: CGFloat = 56
    private static let pulseLaneHeight: CGFloat = 44

    public init(
        session: VitalsSession,
        events: [DesaturationEvent],
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date
    ) {
        self.session = session
        self.events = events
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
    }

    public var body: some View {
        GeometryReader { proxy in
            let plotWidth = max(1, proxy.size.width - Self.labelWidth)
            let viewport = TimelineViewport(normalizing: viewportStart, end: viewportEnd)
            let geometry = SleepTimelineGeometry(
                totalStart: night.timelineStart,
                totalEnd: night.timelineEnd,
                viewport: viewport,
                canvasWidth: plotWidth,
                canvasHeight: proxy.size.height
            )
            let envelope = VitalsEnvelopeBuilder().build(
                session: session,
                viewport: viewport,
                pixelWidth: Int(plotWidth.rounded())
            )

            VStack(alignment: .leading, spacing: 6) {
                labelled("EVENTS") {
                    DesaturationRailView(events: events, geometry: geometry)
                }
                labelled("SpO₂") {
                    VitalsEnvelopeLane(
                        envelope: envelope, measure: .spo2, laneHeight: Self.spo2LaneHeight
                    )
                }
                labelled("PULSE") {
                    VitalsEnvelopeLane(
                        envelope: envelope, measure: .pulse, laneHeight: Self.pulseLaneHeight
                    )
                }
                legend
            }
        }
        .frame(height: Self.totalHeight)
    }

    static var totalHeight: CGFloat {
        DesaturationRailView.railHeight + spo2LaneHeight + pulseLaneHeight + 60
    }

    private func labelled<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
        }
    }

    /// Numeric labels, never verdicts. The threshold is a display choice; a word like
    /// "Critical" would be an interpretation, which the app does not make.
    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(VitalsColorZone.allCases, id: \.self) { zone in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.color)
                        .frame(width: 9, height: 9)
                    Text(zone.legendLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, Self.labelWidth)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Vitals lanes") {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    var spo2 = [UInt8](repeating: 95, count: 3_600)
    for index in 1_200..<1_260 { spo2[index] = 82 }
    for index in 2_400..<2_430 { spo2[index] = 73 }
    let session = VitalsSession(
        id: "preview",
        startDate: start,
        spo2: spo2,
        pulse: (0..<3_600).map { UInt8(55 + ($0 % 20)) },
        motion: [UInt8](repeating: 0, count: 3_600),
        sourceFileNames: ["preview.csv"]
    )
    let night = AssembledNight(
        date: start,
        coreWindowStart: start, coreWindowEnd: session.endDate,
        detectedStart: start, detectedEnd: session.endDate,
        rawIntervals: [], primaryLaneIntervals: [], displayLaneIntervals: [],
        conflicts: [], summary: .empty, hasSleepData: true,
        vitalsExtent: session.dateInterval
    )
    return VitalsLanesView(
        session: session,
        events: DesaturationDetector().events(in: session),
        night: night,
        viewportStart: session.startDate,
        viewportEnd: session.endDate
    )
    .padding()
}
```

- [ ] **Step 4: Build and check the preview**

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: build succeeds. Open `SleepDaddy/Views/VitalsLanesView.swift` in Xcode and confirm the preview renders: two dips visible, the deeper one red, the shallower one crossing yellow into red, the rail marking both.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Views/DesaturationRailView.swift SleepDaddy/Views/VitalsEnvelopeLane.swift SleepDaddy/Views/VitalsLanesView.swift
git commit -m "feat: render the desaturation rail and vitals envelope lanes"
```

---

## Task 12: NightBrowserModel integration

**Files:**
- Modify: `SleepDaddy/ViewModels/NightBrowserModel.swift`
- Test: `SleepDaddyTests/NightBrowserModelVitalsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SleepDaddyTests/NightBrowserModelVitalsTests.swift`:

```swift
import Testing
import Foundation
@testable import SleepDaddy

/// An in-memory store so the model can be exercised without touching the file system.
final class InMemoryVitalsStore: VitalsStore, @unchecked Sendable {
    var sessions: [VitalsSession] = []

    func importRecording(_ data: Data, originalName: String) throws -> VitalsRecordingDescriptor {
        let session = try CheckmeCSVParser().parse(data, fileName: originalName)
        sessions.append(session)
        return VitalsRecordingDescriptor(
            start: session.startDate, end: session.endDate,
            url: URL(fileURLWithPath: "/dev/null")
        )
    }

    func allDescriptors() throws -> [VitalsRecordingDescriptor] {
        sessions.map {
            VitalsRecordingDescriptor(
                start: $0.startDate, end: $0.endDate,
                url: URL(fileURLWithPath: "/\($0.id)")
            )
        }
    }

    func descriptors(overlapping interval: DateInterval) throws -> [VitalsRecordingDescriptor] {
        try allDescriptors().filter { $0.dateInterval.intersects(interval) }
    }

    func loadSession(for descriptor: VitalsRecordingDescriptor) throws -> VitalsSession {
        sessions.first { $0.startDate == descriptor.start }!
    }

    func originalCSV(for descriptor: VitalsRecordingDescriptor) throws -> Data { Data() }
}

struct NightBrowserModelVitalsTests {
    private func session(start: Date, count: Int) -> VitalsSession {
        VitalsSession(
            id: "s-\(start.timeIntervalSinceReferenceDate)",
            startDate: start,
            spo2: Array(repeating: UInt8(95), count: count),
            pulse: Array(repeating: UInt8(60), count: count),
            motion: Array(repeating: UInt8(0), count: count),
            sourceFileNames: []
        )
    }

    @Test func aNightWithNoVitalsExposesNoSession() async {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        await model.loadData()
        #expect(model.selectedVitalsSession == nil)
        #expect(model.selectedDesaturationEvents.isEmpty)
    }

    @Test func aSessionOverlappingTheSelectedNightIsExposed() async {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store,
            now: { Date() }
        )
        await model.loadData()

        guard let night = model.selectedAssembledNight, night.hasSleepData else { return }
        store.sessions = [session(start: night.detectedStart, count: 1_000)]
        await model.loadVitalsForSelectedNight()

        #expect(model.selectedVitalsSession != nil)
    }

    @Test func theSelectedNightCarriesTheVitalsExtent() async {
        let store = InMemoryVitalsStore()
        let model = NightBrowserModel(
            store: FixtureSleepStore(), vitalsStore: store, now: { Date() }
        )
        await model.loadData()

        guard let night = model.selectedAssembledNight, night.hasSleepData else { return }
        // Start an hour before the detected sleep so the extent must widen.
        let early = night.detectedStart.addingTimeInterval(-3_600)
        store.sessions = [session(start: early, count: 3_000)]
        await model.loadVitalsForSelectedNight()

        let updated = try! #require(model.selectedAssembledNight)
        #expect(updated.vitalsExtent != nil)
        #expect(updated.timelineStart <= early)
    }
}
```

- [ ] **Step 2: Modify NightBrowserModel**

Add stored state after `allFetchedIntervals`:

```swift
    private let vitalsStore: (any VitalsStore)?
    private let detector = DesaturationDetector()

    public private(set) var selectedVitalsSession: VitalsSession?
    public private(set) var selectedDesaturationEvents: [DesaturationEvent] = []
```

Change the initializer signature and body:

```swift
    public init(
        store: HealthKitSleepStoreProtocol = HealthKitSleepStore(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        vitalsStore: (any VitalsStore)? = try? FileVitalsStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.vitalsStore = vitalsStore
        self.now = now
        // …rest unchanged
```

Add the loader:

```swift
    /// Resolves vitals for the selected night and attaches the extent to it.
    ///
    /// Runs off the main actor: a full recording is roughly 22,000 samples to decompress
    /// and parse. It never touches rendering, which reads the in-memory arrays.
    @MainActor
    public func loadVitalsForSelectedNight() async {
        guard let vitalsStore, let night = selectedAssembledNight else {
            selectedVitalsSession = nil
            selectedDesaturationEvents = []
            return
        }

        // Search a generous window so a recording starting before the detected sleep is
        // still found. The extent, not this window, decides what is drawn.
        let searchWindow = DateInterval(
            start: night.detectedStart.addingTimeInterval(-6 * 3_600),
            end: night.detectedEnd.addingTimeInterval(6 * 3_600)
        )

        let detector = self.detector
        let loaded: (VitalsSession, [DesaturationEvent])? = await Task.detached(priority: .userInitiated) {
            guard let session = try? vitalsStore.session(covering: searchWindow) else { return nil }
            return (session, detector.events(in: session))
        }.value

        guard let (session, events) = loaded else {
            selectedVitalsSession = nil
            selectedDesaturationEvents = []
            attachVitalsExtent(nil)
            return
        }

        selectedVitalsSession = session
        selectedDesaturationEvents = events
        attachVitalsExtent(session.dateInterval)
    }

    private func attachVitalsExtent(_ extent: DateInterval?) {
        guard let index = currentNightIndex else { return }
        assembledNights[index] = assembledNights[index].withVitalsExtent(extent)
    }

    /// Imports a CSV and refreshes the current night if the recording lands on it.
    @MainActor
    public func importVitals(from url: URL) async throws {
        guard let vitalsStore else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        try vitalsStore.importRecording(data, originalName: url.lastPathComponent)
        await loadVitalsForSelectedNight()
    }
```

In `selectedDate`'s `didSet`, drop the stale session so a night change never shows the previous night's data:

```swift
    public var selectedDate: Date = Calendar.current.startOfDay(for: Date()) {
        didSet {
            selectedInterval = nil
            selectedVitalsSession = nil
            selectedDesaturationEvents = []
            resetViewportToSelectedNight()
        }
    }
```

At the end of `loadData`, after `appState = .loaded`, add:

```swift
            await loadVitalsForSelectedNight()
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: the new suite passes and no existing suite regresses.

- [ ] **Step 4: Commit**

```bash
git add SleepDaddy/ViewModels/NightBrowserModel.swift SleepDaddyTests/NightBrowserModelVitalsTests.swift
git commit -m "feat: load vitals for the selected night"
```

---

## Task 13: Compose the lanes and add the import entry point

**Files:**
- Modify: `SleepDaddy/Views/SelectedNightDetailView.swift`
- Modify: `SleepDaddy/Views/SettingsView.swift`
- Create: `SleepDaddy/Views/VitalsImportButton.swift`

- [ ] **Step 1: Compose the lanes**

In `SleepDaddy/Views/SelectedNightDetailView.swift`, replace `timelineCanvas(night:)`:

```swift
    private func timelineCanvas(night: AssembledNight) -> some View {
        VStack(spacing: 8) {
            SleepTimelineCanvas(
                night: night,
                viewportStart: model.viewportStart,
                viewportEnd: model.viewportEnd,
                selectedIntervalID: model.selectedInterval?.id,
                onSelectInterval: { interval in
                    model.selectedInterval = interval
                },
                onUpdateViewport: { newStart, newEnd in
                    model.updateViewport(start: newStart, end: newEnd)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Absent entirely when the night has no vitals — no placeholder, no empty
            // chrome. The app looks exactly as it did before the feature existed.
            if let session = model.selectedVitalsSession {
                VitalsLanesView(
                    session: session,
                    events: model.selectedDesaturationEvents,
                    night: night,
                    viewportStart: model.viewportStart,
                    viewportEnd: model.viewportEnd
                )
            }
        }
        .padding(.horizontal, 16)
    }
```

- [ ] **Step 2: Write the import button**

Create `SleepDaddy/Views/VitalsImportButton.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Files-picker entry point for a Checkme O2 Max CSV export.
public struct VitalsImportButton: View {
    @Bindable var model: NightBrowserModel
    @State private var isPresented = false
    @State private var errorMessage: String?

    public init(model: NightBrowserModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Import Pulse Oximeter CSV", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            Task { await handle(result) }
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handle(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    try await model.importVitals(from: url)
                } catch let error as VitalsImportError {
                    errorMessage = error.userMessage
                    return
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
        }
    }
}
```

- [ ] **Step 3: Add it to Settings**

`SettingsView` currently takes two `Binding<Int>`s and a dismiss closure — it has no model
reference. Add one.

In `SleepDaddy/Views/SettingsView.swift`, change the stored properties and initializer:

```swift
public struct SettingsView: View {
    @Bindable var model: NightBrowserModel
    @Binding var coreStartHour: Int
    @Binding var coreEndHour: Int
    let onDismiss: () -> Void

    public init(
        model: NightBrowserModel,
        coreStartHour: Binding<Int>,
        coreEndHour: Binding<Int>,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self._coreStartHour = coreStartHour
        self._coreEndHour = coreEndHour
        self.onDismiss = onDismiss
    }
```

Then add a section inside the `Form`, immediately after the `Core Night Window` section:

```swift
                Section(
                    header: Text("Pulse Oximeter"),
                    footer: Text("Import a CSV export from the Checkme O2 Max. Recordings split by the device's 10-hour limit are joined automatically.")
                ) {
                    VitalsImportButton(model: model)
                }
```

Update the call site at `SleepDaddy/Views/ContentView.swift:206` to pass the model:

```swift
                SettingsView(
                    model: model,
                    coreStartHour: Binding(
                        get: { model.preferences.coreWindowStartHour },
                        set: { start in model.updateCoreWindow(startHour: start, endHour: model.preferences.coreWindowEndHour) }
                    ),
                    coreEndHour: Binding(
                        get: { model.preferences.coreWindowEndHour },
                        set: { end in model.updateCoreWindow(startHour: model.preferences.coreWindowStartHour, endHour: end) }
                    ),
                    onDismiss: { model.showSettings = false }
                )
```

- [ ] **Step 4: Build and check**

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add SleepDaddy/Views/
git commit -m "feat: compose vitals lanes and add CSV import"
```

---

## Task 14: Document type registration and open-in support

**Files:**
- Modify: `project.yml`
- Modify: `SleepDaddy/SleepDaddyApp.swift`

This registers SleepDaddy as a CSV handler, giving "Open in SleepDaddy" in the share sheet's action list. A Share Extension — needed for a slot in the app icon row — is **out of scope**; see the spec's decision point.

- [ ] **Step 1: Add the document type**

In `project.yml`, under `targets.SleepDaddy.info.properties`, add:

```yaml
        LSSupportsOpeningDocumentsInPlace: true
        UISupportsDocumentBrowser: false
        CFBundleDocumentTypes:
          - CFBundleTypeName: "Pulse Oximeter CSV"
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - public.comma-separated-values-text
```

`LSHandlerRank: Alternate` is deliberate — SleepDaddy is not claiming to own every CSV on the device, only offering to open one.

- [ ] **Step 2: Regenerate the project**

```bash
xcodegen generate
```

Expected: no errors. `SleepDaddy.xcodeproj` and `Info.plist` are generated and **must not be committed**.

- [ ] **Step 3: Handle incoming URLs**

In `SleepDaddy/SleepDaddyApp.swift`, add `.onOpenURL` to the root view:

```swift
                .onOpenURL { url in
                    Task { try? await model.importVitals(from: url) }
                }
```

Place it beside the existing `.task` / scene-phase modifiers on the same view that owns `model`.

- [ ] **Step 4: Build and verify registration**

```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Then confirm the key survived generation:

```bash
plutil -p DerivedData/Build/Products/Debug-iphonesimulator/SleepDaddy.app/Info.plist | grep -A6 CFBundleDocumentTypes
```

Expected: the document type block is present with `public.comma-separated-values-text`.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

Expected: all suites pass. Check the output lists every suite by name.

- [ ] **Step 6: Commit**

```bash
git add project.yml SleepDaddy/SleepDaddyApp.swift
git commit -m "feat: register SleepDaddy as a CSV document handler"
```

---

## Task 15: End-to-end verification with the real export

**Files:** none — this is a manual verification pass.

- [ ] **Step 1: Get the real files onto the simulator**

The reference export lives at `~/Downloads/Checkme O2 Max _2026*.csv`. Drag both onto the booted simulator to drop them into Files, or use:

```bash
xcrun simctl addmedia booted ~/Downloads/"Checkme O2 Max _20260803180248.csv"
```

If `addmedia` rejects a CSV, drag-and-drop onto the simulator window instead.

- [ ] **Step 2: Import and verify against known values**

Run the app, open Settings, import both files. Then confirm on the night of 2026-08-03:

- Both files import; the second is **not** a separate session — the 4-second gap joins them
- The SpO₂ lane spans roughly 18:02 to 06:24
- The timeline pans back to 18:02, before the 19:00 core window
- A red dip is visible around 23:07 — that is the 73% nadir
- Desaturations cluster visibly between roughly 22:00 and 00:45
- The pulse lane is a single colour throughout
- The legend reads `90% and above` / `85–90%` / `Below 85%`

- [ ] **Step 3: Verify the envelope guarantee by eye**

Zoom fully out. The 23:07 dip must still reach the red zone — narrow, but at full depth. Zoom in to a three-minute window around it and confirm individual samples resolve. If the dip softens as you zoom out, `VitalsEnvelopeBuilder` is averaging and Task 5's tests are lying.

- [ ] **Step 4: Verify a night without vitals is unchanged**

Navigate to a night with no imported recording. The rail and both lanes must be **absent entirely** — no empty frames, no placeholder text.

- [ ] **Step 5: Commit any fixes**

If any check fails, fix it with a test that would have caught it, then commit.

---

## Self-Review Notes

**Spec coverage.** Every section maps to a task: data model → 1, 5, 6, 7; parsing → 2, 3; stitching → 4; envelope → 5; colour → 6; detection → 7; geometry → 8; storage and compression → 9; timeline extent → 10; lane composition and the dual-axis prohibition → 8, 11; view-model integration → 12; import and document types → 13, 14; error handling → surfaced in 3, 9, 13.

**Spec corrections made while writing this plan.** Two, both already applied to the spec:

1. The spec recorded zlib **level 6**. Apple's `NSData.compressed(using:)` exposes no
   level parameter — the Compression framework chooses. The spec now says so and
   explains why pinning a level is not worth a dependency.
2. `VitalsSession.sampleInterval` was a stored property. It is a static constant, since
   the cadence is a property of the device rather than of a recording.

**Deliberately not covered**, per the spec's non-goals: iCloud, the Share Extension, vitals in the multi-night strip or share card, configurable thresholds, HealthKit vitals, and pulse severity colouring.
