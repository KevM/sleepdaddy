import XCTest

/// Drives the app through a narrated walkthrough of every reviewable feature, at a
/// pace a person can follow. Intended to be screen-recorded — see
/// `Scripts/record-demo.sh`, which starts `simctl io recordVideo` around this run
/// and produces the video linked from the App Review notes.
///
/// On the simulator the app is backed by `FixtureSleepStore`, so the walkthrough
/// shows a full multi-stage night without HealthKit data on the host. Nothing here
/// asserts on pixels; failures mean a control went missing, not that a drawing
/// changed.
///
/// The sections below are deliberately in the same order as the walkthrough on
/// the demo page. They are not timestamped: `simctl io recordVideo` only emits a
/// frame when the screen changes and its timestamps do not advance faithfully
/// through a static pause, so wall-clock marks taken during the run do not map
/// onto the recording's timeline. Measured against the finished video they landed
/// anywhere from four seconds early to two late, in both directions, so the page
/// lists the sections in order instead of linking into them.
///
/// Portrait only. The device recording stays in the display's native orientation,
/// so a rotation mid-run yields a sideways segment; landscape is covered by the
/// full-resolution App Store screenshot on the demo page instead.
///
/// This lives in the screenshots target so it shares the app build. It is *not*
/// part of the App Store screenshot pass — run it explicitly with
/// `-only-testing:SleepDaddyScreenshots/DemoWalkthrough`, and exclude it from the
/// screenshot pass with `-skip-testing:SleepDaddyScreenshots/DemoWalkthrough`.
final class DemoWalkthrough: XCTestCase {
    private var app: XCUIApplication!

    /// The walkthrough is paced for video, so a beat is a real pause, not a poll
    /// interval. Every wait below still uses `waitForExistence` for correctness;
    /// these sleeps exist purely so the recording is watchable.
    private enum Beat {
        static let short: TimeInterval = 1.0
        static let read: TimeInterval = 2.0
        static let dwell: TimeInterval = 3.0
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testRecordDemoWalkthrough() throws {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "Timeline never finished loading")

        // 1. The night at rest: header date, total duration, full stepped timeline.
        beat(Beat.dwell)

        // 2. Tap an interval to raise the inspector — stage, exact clock times, and
        //    the HealthKit source the sample came from. The canvas is a drawn
        //    surface, so target it positionally rather than by element. This runs
        //    before any zoom, where the interval under the point is known.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.65)).tap()
        let inspector = app.staticTexts["Interval Details"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5), "Interval inspector never appeared")
        beat(Beat.dwell)
        dismissSheet()

        // 3. Pinch to zoom into the timeline. Two passes in the same direction read
        //    as one deliberate zoom rather than a twitch.
        app.pinch(withScale: 2.1, velocity: 1.1)
        beat(Beat.short)
        app.pinch(withScale: 1.8, velocity: 1.0)
        beat(Beat.dwell)

        // 4. Pan across the zoomed night in both directions.
        drag(fromX: 0.72, toX: 0.28)
        beat(Beat.short)
        drag(fromX: 0.28, toX: 0.68)
        beat(Beat.read)

        // Back out to the whole night before leaving the timeline.
        app.pinch(withScale: 0.3, velocity: -1.4)
        beat(Beat.read)

        // 5. Night navigation, back and then forward again so the demo ends on the
        //    same night it started with. The fixture generates an identical night
        //    each day, so the date in the header is what changes here, not the shape.
        tap(app.buttons["Previous night"], then: Beat.dwell)
        tap(app.buttons["Previous night"], then: Beat.dwell)
        tap(app.buttons["Next night"], then: Beat.read)
        tap(app.buttons["Next night"], then: Beat.read)

        // 6. Source filtering: open the sheet, toggle a source off and back on so a
        //    reviewer sees the timeline respond, then close.
        tap(app.buttons["Filter sleep sources"], then: Beat.dwell)

        let sourceToggles = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Filter source ")
        )
        XCTAssertGreaterThan(
            sourceToggles.count, 0,
            "Filter sheet listed no sources, so the demo would not show filtering working"
        )
        let firstSource = sourceToggles.element(boundBy: 0)
        tap(firstSource, then: Beat.read)
        tap(firstSource, then: Beat.short)
        dismissSheet()
        beat(Beat.read)

        // 7. Settings: the adaptive night-boundary window.
        tap(settings, then: Beat.dwell)
        dismissSheet()
        beat(Beat.short)

        // 8. Share: renders the timeline card into the system share sheet. Dismissed
        //    without sending anything.
        tap(app.buttons["Share timeline"], then: Beat.dwell)
        dismissShareSheet()
        beat(Beat.read)
    }

    // MARK: - Helpers

    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// A slow horizontal drag across the timeline. `press(forDuration:thenDragTo:)`
    /// produces a continuous move the pan recognizer tracks, where `swipe` would
    /// flick past most of the night in a frame or two.
    private func drag(fromX: CGFloat, toX: CGFloat) {
        let y: CGFloat = 0.62
        app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: y))
            .press(
                forDuration: 0.35,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: y)),
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
    }

    /// Taps a control the walkthrough depends on, failing the run if it isn't
    /// there. Every section of the demo has to appear in the recording, so a
    /// renamed accessibility label must stop the run rather than quietly drop a
    /// section and leave a short video that still reports success.
    private func tap(
        _ element: XCUIElement,
        then seconds: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: 5),
            "Missing control: \(element)",
            file: file, line: line
        )
        XCTAssertTrue(element.isEnabled, "Disabled control: \(element)", file: file, line: line)
        element.tap()
        beat(seconds)
    }

    /// Every sheet in the app carries a Done button; fall back to a swipe down for
    /// anything that doesn't. Unlike the controls above, either route is fine, so
    /// this only has to leave no sheet behind.
    private func dismissSheet() {
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 2), done.isHittable {
            done.tap()
            beat(Beat.short)
        } else {
            swipeSheetAway()
        }
        XCTAssertFalse(
            app.buttons["Done"].firstMatch.exists,
            "A sheet was still open after dismissing it"
        )
    }

    /// `UIActivityViewController` has a Close button rather than Done.
    private func dismissShareSheet() {
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 2), close.isHittable {
            close.tap()
            beat(Beat.short)
            return
        }
        swipeSheetAway()
    }

    private func swipeSheetAway() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            )
        beat(Beat.short)
    }
}
