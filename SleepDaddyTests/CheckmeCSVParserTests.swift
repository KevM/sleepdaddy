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

    @Test func acceptsHeaderWithUTF8BOM() throws {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let text = Self.header + "\n18:02:48 Aug 03 2026,96,70,0,0,0\n18:02:50 Aug 03 2026,95,69,1,0,0"
        var data = bom
        data.append(Data(text.utf8))
        let session = try parse(data)
        #expect(session.sampleCount == 2)
        #expect(session.spo2 == [96, 95])
    }

    @Test func acceptsFourColumnHeader() throws {
        let text = "Time,Oxygen Level,Pulse Rate,Motion\n18:02:48 Aug 03 2026,96,70,0\n18:02:50 Aug 03 2026,95,69,1"
        let session = try parse(Data(text.utf8))
        #expect(session.sampleCount == 2)
        #expect(session.spo2 == [96, 95])
    }

    @Test func acceptsQuotedHeaderAndData() throws {
        let text = "\"Time\",\"Oxygen Level\",\"Pulse Rate\",\"Motion\"\n\"18:02:48 Aug 03 2026\",\"96\",\"70\",\"0\"\n\"18:02:50 Aug 03 2026\",\"95\",\"69\",\"1\""
        let session = try parse(Data(text.utf8))
        #expect(session.sampleCount == 2)
        #expect(session.spo2 == [96, 95])
    }

    @Test func acceptsSpO2Header() throws {
        let text = "Time,SpO2,Pulse Rate,Motion\n18:02:48 Aug 03 2026,96,70,0\n18:02:50 Aug 03 2026,95,69,1"
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
