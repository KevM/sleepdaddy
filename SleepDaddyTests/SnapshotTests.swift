import Testing
import SwiftUI
import UIKit
@testable import SleepDaddy

struct SnapshotTests {
    @Test @MainActor func testTimelineCardSnapshotComposition() throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "s1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(7200), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s2", startDate: coreStart.addingTimeInterval(7200), endDate: coreStart.addingTimeInterval(14400), stage: .deep, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s3", startDate: coreStart.addingTimeInterval(14400), endDate: coreStart.addingTimeInterval(18000), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health")
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )

        let shareCard = ShareTimelineCardView(
            night: night,
            viewportStart: night.detectedStart,
            viewportEnd: night.detectedEnd,
            sourceFilterDescription: "Apple Watch"
        )
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 2.0
        guard let currentImage = renderer.uiImage,
              let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render current image snapshot PNG")
            return
        }

        // Reference PNG file path
        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("share_card_snapshot.png")

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            // Save baseline reference PNG
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            // Load baseline PNG and compare CGImage pixel dimensions and pixel buffer directly
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG")
                return
            }

            // Compare pixel width and height directly on CGImage
            #expect(cgCurrent.width == cgReference.width, "Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")

            // Compare raw bitmap pixel buffers directly
            let imagesMatch = compareImages(cgCurrent: cgCurrent, cgReference: cgReference)
            #expect(imagesMatch, "Rendered snapshot image pixels do not match reference PNG snapshot")
        }
    }

    private func compareImages(cgCurrent: CGImage, cgReference: CGImage) -> Bool {
        let width = cgCurrent.width
        let height = cgCurrent.height

        guard width == cgReference.width && height == cgReference.height else { return false }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height

        var data1 = [UInt8](repeating: 0, count: totalBytes)
        var data2 = [UInt8](repeating: 0, count: totalBytes)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx1 = CGContext(data: &data1, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let ctx2 = CGContext(data: &data2, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }

        ctx1.draw(cgCurrent, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx2.draw(cgReference, in: CGRect(x: 0, y: 0, width: width, height: height))

        return data1 == data2
    }

    @MainActor
    @Test func nightHeaderDateFormattingUsesExplicitLocaleAndTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-07-25T12:00:00Z")!
        let formatted = NightHeaderView.formattedDate(
            date,
            locale: Locale(identifier: "fr_FR"),
            timeZone: TimeZone(secondsFromGMT: 14 * 3600)!
        )

        #expect(formatted == "dim., juil. 26")
    }

    @Test @MainActor func testNightHeaderSnapshotComposition() throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "s1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(7200), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s2", startDate: coreStart.addingTimeInterval(7200), endDate: coreStart.addingTimeInterval(14400), stage: .deep, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "s3", startDate: coreStart.addingTimeInterval(14400), endDate: coreStart.addingTimeInterval(18000), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health")
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )

        let headerView = NightHeaderView(
            night: night,
            canGoPrevious: true,
            canGoNext: true,
            onPrevious: {},
            onNext: {},
            onSelectDate: { _ in }
        )
        .frame(width: 393, height: 60)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)

        let renderer = ImageRenderer(content: headerView)
        renderer.scale = 2.0
        guard let currentImage = renderer.uiImage,
              let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render current image snapshot PNG")
            return
        }

        // Reference PNG file path
        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("sleep-timeline-redesign-reference.png")

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            // Save baseline reference PNG
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            // Load baseline PNG and compare CGImage pixel dimensions and pixel buffer directly
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG")
                return
            }

            #expect(cgCurrent.width == cgReference.width, "Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")

            let imagesMatch = compareImages(cgCurrent: cgCurrent, cgReference: cgReference)
            #expect(imagesMatch, "Rendered snapshot image pixels do not match reference PNG snapshot")
        }
    }

    @Test @MainActor func testSleepTimelineCanvasSnapshotComposition() throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "inbed", startDate: coreStart, endDate: coreStart.addingTimeInterval(12 * 3600), stage: .inBed, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(5400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "core1", startDate: coreStart.addingTimeInterval(5400), endDate: coreStart.addingTimeInterval(10800), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "unspecified1", startDate: coreStart.addingTimeInterval(10800), endDate: coreStart.addingTimeInterval(16200), stage: .asleepUnspecified, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "rem1", startDate: coreStart.addingTimeInterval(16200), endDate: coreStart.addingTimeInterval(21600), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk2", startDate: coreStart.addingTimeInterval(21600), endDate: coreStart.addingTimeInterval(23400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "conflict_oura", startDate: coreStart.addingTimeInterval(12600), endDate: coreStart.addingTimeInterval(14400), stage: .core, sourceName: "Oura Ring", sourceIdentifier: "com.oura.ring")
        ]

        let assembler = NightAssembler()
        let night = assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )
        let selectedUnspecifiedID = night.primaryLaneIntervals.first {
            $0.stage == .asleepUnspecified
        }!.id

        let canvas = SleepTimelineCanvas(
            night: night,
            viewportStart: night.detectedStart,
            viewportEnd: night.detectedEnd,
            selectedIntervalID: selectedUnspecifiedID,
            onSelectInterval: { _ in },
            onUpdateViewport: { _, _ in }
        )
        .frame(width: 393, height: 320)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.timelineInteractionEnabled, false)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2.0
        guard let currentImage = renderer.uiImage,
              let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render timeline canvas snapshot PNG")
            return
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("timeline_canvas_snapshot.png")

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG")
                return
            }

            #expect(cgCurrent.width == cgReference.width, "Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")

            let imagesMatch = compareImages(cgCurrent: cgCurrent, cgReference: cgReference)
            #expect(imagesMatch, "Rendered snapshot image pixels do not match reference PNG snapshot")
        }
    }

    @Test @MainActor func testCompactSourceFilterButtonSnapshotComposition() throws {
        let filterButton = CompactSourceFilterButton(
            availableSources: ["com.apple.health": "Apple Watch", "com.oura.ring": "Oura Ring"],
            selectedSourceIDs: ["com.apple.health"],
            onToggleSource: { _ in },
            onClearFilter: {}
        )
        .frame(width: 44, height: 44)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: filterButton)
        renderer.scale = 2.0
        guard let currentImage = renderer.uiImage,
              let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render compact source filter button snapshot PNG")
            return
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("compact_source_filter_button_snapshot.png")

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG")
                return
            }

            #expect(cgCurrent.width == cgReference.width, "Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")

            let imagesMatch = compareImages(cgCurrent: cgCurrent, cgReference: cgReference)
            #expect(imagesMatch, "Rendered snapshot image pixels do not match reference PNG snapshot")
        }
    }

    private func makeFixtureNight() -> AssembledNight {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 25
        components.hour = 19
        let coreStart = calendar.date(from: components)!

        let fixtureIntervals = [
            NormalizedSleepInterval(id: "inbed", startDate: coreStart, endDate: coreStart.addingTimeInterval(12 * 3600), stage: .inBed, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk1", startDate: coreStart.addingTimeInterval(3600), endDate: coreStart.addingTimeInterval(5400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "core1", startDate: coreStart.addingTimeInterval(5400), endDate: coreStart.addingTimeInterval(10800), stage: .core, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "deep1", startDate: coreStart.addingTimeInterval(10800), endDate: coreStart.addingTimeInterval(16200), stage: .deep, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "rem1", startDate: coreStart.addingTimeInterval(16200), endDate: coreStart.addingTimeInterval(21600), stage: .rem, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "awk2", startDate: coreStart.addingTimeInterval(21600), endDate: coreStart.addingTimeInterval(23400), stage: .awake, sourceName: "Apple Watch", sourceIdentifier: "com.apple.health"),
            NormalizedSleepInterval(id: "conflict_oura", startDate: coreStart.addingTimeInterval(12600), endDate: coreStart.addingTimeInterval(14400), stage: .core, sourceName: "Oura Ring", sourceIdentifier: "com.oura.ring")
        ]

        let assembler = NightAssembler()
        return assembler.assembleNight(
            for: coreStart,
            allNormalizedIntervals: fixtureIntervals,
            preferences: .default
        )
    }

    @MainActor
    private func assertSnapshot<V: View>(
        of view: V,
        named name: String,
        width: CGFloat,
        height: CGFloat
    ) throws {
        let host = view
            .frame(width: width, height: height)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .environment(\.timelineInteractionEnabled, false)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 2.0
        guard let currentImage = renderer.uiImage,
              let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render snapshot PNG for \(name)")
            return
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("\(name).png")

        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG for \(name)")
                return
            }

            #expect(cgCurrent.width == cgReference.width, "\(name): Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "\(name): Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")

            let imagesMatch = compareImages(cgCurrent: cgCurrent, cgReference: cgReference)
            #expect(imagesMatch, "Rendered snapshot image pixels for \(name) do not match reference PNG snapshot")
        }
    }

    @MainActor
    private func assertHostedSnapshot<V: View>(
        of view: V,
        named name: String,
        width: CGFloat,
        height: CGFloat,
        isReady: @MainActor () -> Bool
    ) async throws {
        let size = CGSize(width: width, height: height)
        let controller = UIHostingController(rootView: view)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            Issue.record("Failed to find a window scene for hosted snapshot \(name)")
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.isHidden = false

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(isReady(), "\(name): Hosted content did not reach its expected state")
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let currentImage = renderer.image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(10))

        guard let currentPNGData = currentImage.pngData(),
              let cgCurrent = currentImage.cgImage else {
            Issue.record("Failed to render hosted snapshot PNG for \(name)")
            return
        }

        let testFileURL = URL(fileURLWithPath: #filePath)
        let referenceDir = testFileURL.deletingLastPathComponent().appendingPathComponent("ReferenceSnapshots")
        let referenceURL = referenceDir.appendingPathComponent("\(name).png")
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: referenceURL.path) {
            try fileManager.createDirectory(at: referenceDir, withIntermediateDirectories: true)
            try currentPNGData.write(to: referenceURL)
            #expect(fileManager.fileExists(atPath: referenceURL.path))
        } else {
            let referenceData = try Data(contentsOf: referenceURL)
            guard let referenceImage = UIImage(data: referenceData),
                  let cgReference = referenceImage.cgImage else {
                Issue.record("Failed to load reference image snapshot PNG for \(name)")
                return
            }

            #expect(cgCurrent.width == cgReference.width, "\(name): Pixel width mismatch (\(cgCurrent.width) vs \(cgReference.width))")
            #expect(cgCurrent.height == cgReference.height, "\(name): Pixel height mismatch (\(cgCurrent.height) vs \(cgReference.height))")
            #expect(
                compareImages(cgCurrent: cgCurrent, cgReference: cgReference),
                "Rendered snapshot image pixels for \(name) do not match reference PNG snapshot"
            )
        }
    }

    @Test @MainActor func testSnapshotEmptyLoadedNight() async throws {
        var fixtureCalendar = Calendar(identifier: .gregorian)
        fixtureCalendar.timeZone = .current
        let now = fixtureCalendar.date(
            from: DateComponents(year: 2026, month: 7, day: 25, hour: 12)
        )!
        let testDefaults = UserDefaults(suiteName: "SnapshotTests.EmptyLoadedNight")!
        testDefaults.removePersistentDomain(forName: "SnapshotTests.EmptyLoadedNight")
        let model = NightBrowserModel(
            store: FixtureSleepStore(customIntervals: []),
            preferencesStore: PreferencesStore(userDefaults: testDefaults),
            now: { now }
        )
        await model.loadData()

        #expect(model.appState == .loaded)
        #expect(model.selectedAssembledNight?.hasSleepData == false)
        let selectedDate = fixtureCalendar.dateComponents(
            [.year, .month, .day],
            from: model.selectedDate
        )
        #expect(selectedDate == DateComponents(year: 2026, month: 7, day: 24))

        let content = ContentView(model: model)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        try await assertHostedSnapshot(
            of: content,
            named: "snapshot_empty_loaded_night",
            width: 393,
            height: 520,
            isReady: { model.appState == .loaded }
        )
    }

    @Test @MainActor func testSnapshotPortraitLightMode() throws {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .light)
        try assertSnapshot(of: composite, named: "snapshot_portrait_light", width: 393, height: 520)
    }

    @Test @MainActor func testSnapshotPortraitDarkMode() throws {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
        try assertSnapshot(of: composite, named: "snapshot_portrait_dark", width: 393, height: 520)
    }

    @Test @MainActor func testSnapshotLandscape() throws {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
        try assertSnapshot(of: composite, named: "snapshot_landscape", width: 852, height: 460)
    }

    @Test @MainActor func testSnapshotDynamicType() throws {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .accessibility2)
        try assertSnapshot(of: composite, named: "snapshot_dynamic_type", width: 393, height: 600)
    }

    @Test @MainActor func testSnapshotReduceMotion() throws {
        let night = makeFixtureNight()
        let composite = NightDetailCompositeView(night: night)
            .environment(\.colorScheme, .dark)
            .environment(\.accessibilityReduceMotionOverride, true)
        try assertSnapshot(of: composite, named: "snapshot_reduce_motion", width: 393, height: 520)
    }
}

private struct NightDetailCompositeView: View {
    let night: AssembledNight

    var body: some View {
        VStack(spacing: 12) {
            NightHeaderView(
                night: night,
                canGoPrevious: true,
                canGoNext: true,
                onPrevious: {},
                onNext: {},
                onSelectDate: { _ in }
            )
            SleepTimelineCanvas(
                night: night,
                viewportStart: night.detectedStart,
                viewportEnd: night.detectedEnd,
                selectedIntervalID: nil,
                onSelectInterval: { _ in },
                onUpdateViewport: { _, _ in }
            )
            .frame(height: 320)
            SlimContextNavigator(
                night: night,
                viewportStart: night.detectedStart,
                viewportEnd: night.detectedEnd,
                onUpdateViewport: { _ in }
            )
        }
        .padding(16)
        .background(Color(UIColor.systemGroupedBackground))
    }
}
