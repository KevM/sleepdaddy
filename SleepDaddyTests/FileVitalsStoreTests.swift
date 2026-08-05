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
