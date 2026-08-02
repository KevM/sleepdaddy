import Testing
@testable import SleepDaddy

struct TimelineGestureSessionTests {
    @Test func pinchOnlySessionAfterFastPanSettlesWithZeroVelocity() {
        var session = TimelineGestureSession()

        #expect(session.begin(.pan) == .began)
        #expect(session.end(.pan, velocityX: 1_400) == .settled(velocityX: 1_400))

        #expect(session.begin(.pinch) == .began)
        #expect(session.end(.pinch) == .settled(velocityX: 0))
    }

    @Test func simultaneousPanAndPinchSettleOnlyAfterBothRecognizersEnd() {
        var session = TimelineGestureSession()

        #expect(session.begin(.pan) == .began)
        #expect(session.begin(.pinch) == .none)
        #expect(session.end(.pan, velocityX: -600) == .none)
        #expect(session.end(.pinch) == .settled(velocityX: -600))
    }

    @Test func simultaneousPinchEndingFirstLetsFinalPanCaptureSettlementVelocity() {
        var session = TimelineGestureSession()

        #expect(session.begin(.pan) == .began)
        #expect(session.begin(.pinch) == .none)
        #expect(session.end(.pinch) == .none)
        #expect(session.end(.pan, velocityX: 750) == .settled(velocityX: 750))
    }

    @Test func cancellingOneRecognizerCancelsTheWholeInteractionOnce() {
        var session = TimelineGestureSession()

        #expect(session.begin(.pan) == .began)
        #expect(session.begin(.pinch) == .none)

        #expect(session.cancel(.pinch) == .cancelled)
        #expect(session.end(.pan, velocityX: 900) == .none)
        #expect(!session.acceptsChanges(from: .pan))
        #expect(!session.acceptsChanges(from: .pinch))
    }

    @Test func externalResetInvalidatesCumulativeUpdatesFromOldRecognizers() {
        var session = TimelineGestureSession()

        #expect(session.begin(.pan) == .began)
        #expect(session.acceptsChanges(from: .pan))

        session.reset()

        #expect(!session.acceptsChanges(from: .pan))
        #expect(session.end(.pan, velocityX: 900) == .none)
    }
}
