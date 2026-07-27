import SwiftUI

public final class SleepShareRenderer: @unchecked Sendable {
    public init() {}

    @MainActor
    public func renderShareImage(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        sourceFilterDescription: String
    ) -> UIImage? {
        let card = ShareTimelineCardView(
            night: night,
            viewportStart: viewportStart,
            viewportEnd: viewportEnd,
            sourceFilterDescription: sourceFilterDescription
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0 // High-resolution retina scale
        return renderer.uiImage
    }
}
