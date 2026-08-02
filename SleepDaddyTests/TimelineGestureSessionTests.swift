import Testing
import CoreGraphics
import UIKit
@testable import SleepDaddy

@MainActor
private final class TestVelocityPanGestureRecognizer: UIPanGestureRecognizer {
    let testVelocity: CGPoint

    init(velocity: CGPoint) {
        self.testVelocity = velocity
        super.init(target: nil, action: nil)
    }

    override func velocity(in view: UIView?) -> CGPoint {
        testVelocity
    }
}

struct TimelineGestureSessionTests {
    @Test @MainActor func gestureDelegateAllowsTimelinePanRegardlessOfInitialVelocity() {
        let overlay = TimelineGestureOverlay(
            onInteractionBegan: {},
            onPanChanged: { _ in },
            onPinchChanged: { _, _ in },
            onInteractionEnded: { _ in },
            onInteractionCancelled: {},
            onTap: { _ in }
        )
        let coordinator = overlay.makeCoordinator()

        #expect(coordinator.gestureRecognizerShouldBegin(
            TestVelocityPanGestureRecognizer(velocity: CGPoint(x: 20, y: 80))
        ) == true)
        #expect(coordinator.gestureRecognizerShouldBegin(
            TestVelocityPanGestureRecognizer(velocity: CGPoint(x: 80, y: 20))
        ) == true)
        #expect(coordinator.gestureRecognizerShouldBegin(
            TestVelocityPanGestureRecognizer(velocity: .zero)
        ) == true)
        #expect(coordinator.gestureRecognizerShouldBegin(UIPinchGestureRecognizer()) == true)
    }

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
