import Foundation

public struct TimelineViewportPresentation: Sendable {
    public private(set) var liveViewport: TimelineViewport?

    public init(liveViewport: TimelineViewport? = nil) {
        self.liveViewport = liveViewport
    }

    public func displayedViewport(committed: TimelineViewport) -> TimelineViewport {
        liveViewport ?? committed
    }

    public mutating func updateLiveViewport(_ viewport: TimelineViewport) {
        liveViewport = viewport
    }

    public mutating func clearLiveViewport() {
        liveViewport = nil
    }
}
