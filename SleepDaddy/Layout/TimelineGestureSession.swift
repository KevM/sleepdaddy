import CoreGraphics

enum TimelineGestureKind: Hashable, Sendable {
    case pan
    case pinch
}

enum TimelineGestureSessionEvent: Equatable, Sendable {
    case none
    case began
    case settled(velocityX: CGFloat)
    case cancelled
}

/// Coordinates the shared lifecycle of simultaneous pan and pinch recognizers.
///
/// UIKit reports each recognizer independently, but the timeline treats an overlapping pan
/// and pinch as one interaction. This value type makes that combined lifecycle explicit and
/// keeps pan velocity scoped to the interaction that produced it.
struct TimelineGestureSession: Sendable {
    private var activeKinds: Set<TimelineGestureKind> = []
    private var lastPanVelocityX: CGFloat = 0

    mutating func begin(_ kind: TimelineGestureKind) -> TimelineGestureSessionEvent {
        guard !activeKinds.contains(kind) else { return .none }

        if activeKinds.isEmpty {
            lastPanVelocityX = 0
        }
        activeKinds.insert(kind)
        return activeKinds.count == 1 ? .began : .none
    }

    func acceptsChanges(from kind: TimelineGestureKind) -> Bool {
        activeKinds.contains(kind)
    }

    mutating func end(
        _ kind: TimelineGestureKind,
        velocityX: CGFloat = 0
    ) -> TimelineGestureSessionEvent {
        guard activeKinds.remove(kind) != nil else { return .none }

        if kind == .pan {
            lastPanVelocityX = velocityX
        }
        guard activeKinds.isEmpty else { return .none }
        return .settled(velocityX: lastPanVelocityX)
    }

    mutating func cancel(_ kind: TimelineGestureKind) -> TimelineGestureSessionEvent {
        guard activeKinds.contains(kind) else { return .none }
        reset()
        return .cancelled
    }

    mutating func reset() {
        activeKinds.removeAll()
        lastPanVelocityX = 0
    }
}
