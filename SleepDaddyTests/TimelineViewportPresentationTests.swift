import Testing
import Foundation
@testable import SleepDaddy

struct TimelineViewportPresentationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func liveViewportOverridesCommittedViewport() {
        let committed = TimelineViewport(
            start: start,
            end: start.addingTimeInterval(12 * 3600)
        )
        let live = TimelineViewport(
            start: start.addingTimeInterval(3 * 3600),
            end: start.addingTimeInterval(7 * 3600)
        )
        var presentation = TimelineViewportPresentation()

        presentation.updateLiveViewport(live)

        #expect(presentation.displayedViewport(committed: committed) == live)
    }

    @Test func clearingLiveViewportFallsBackToLatestCommittedViewport() {
        let original = TimelineViewport(
            start: start,
            end: start.addingTimeInterval(12 * 3600)
        )
        let live = TimelineViewport(
            start: start.addingTimeInterval(3 * 3600),
            end: start.addingTimeInterval(7 * 3600)
        )
        let newlyCommitted = TimelineViewport(
            start: start.addingTimeInterval(2 * 3600),
            end: start.addingTimeInterval(8 * 3600)
        )
        var presentation = TimelineViewportPresentation()
        presentation.updateLiveViewport(live)

        presentation.clearLiveViewport()

        #expect(presentation.displayedViewport(committed: newlyCommitted) == newlyCommitted)
        #expect(presentation.displayedViewport(committed: original) == original)
    }
}
