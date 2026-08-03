import XCTest

/// Drives the app through its main screens and attaches a full-screen capture of
/// each one. Run via the SleepDaddyScreenshots scheme; `Scripts/capture-screenshots.sh`
/// wraps the run and exports the attachments as PNGs.
///
/// On the simulator the app is backed by `FixtureSleepStore`, so these captures
/// show a full multi-stage night without needing HealthKit data.
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testCaptureAppStoreScreenshots() {
        // The timeline is drawn once fixture nights are assembled. Wait on the
        // header rather than a fixed sleep so slower simulators still settle.
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "Timeline never finished loading")
        settle()

        capture("01-timeline-portrait")

        // Tap a Core interval near 3 AM to raise the inspector. The canvas is a
        // drawn surface, so target it positionally rather than by element.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.65)).tap()
        settle()
        capture("02-interval-inspector")
        dismissSheet()

        let filter = app.buttons["Filter sleep sources"]
        if filter.waitForExistence(timeout: 5) {
            filter.tap()
            settle()
            capture("03-source-filter")
            dismissSheet()
        }

        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            settle()
            capture("04-settings")
            dismissSheet()
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        settle(seconds: 2)
        capture("05-timeline-landscape")
    }

    // MARK: - Helpers

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// SwiftUI sheet and timeline animations need a beat to finish before a
    /// capture, otherwise screenshots catch a half-presented sheet.
    private func settle(seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Sheets here are dismissed by swiping down from the sheet body; there is no
    /// consistent Done button across them.
    private func dismissSheet() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            )
        settle()
    }
}
