import Testing
import Foundation
import UIKit
@testable import SleepDaddy

struct ShareRendererTests {
    @MainActor
    private func renderFixtureCard(sourceFilterDescription: String?) -> UIImage? {
        let assembler = NightAssembler()
        let sampleDate = Date()
        let sampleIntervals = FixtureSleepStore.generateDefaultFixtures(
            from: sampleDate.addingTimeInterval(-86400),
            to: sampleDate.addingTimeInterval(86400)
        )

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: sampleIntervals,
            preferences: .default
        )

        return SleepShareRenderer().renderShareImage(
            night: assembled,
            viewportStart: assembled.detectedStart,
            viewportEnd: assembled.detectedEnd,
            sourceFilterDescription: sourceFilterDescription
        )
    }

    @Test @MainActor func testShareRendererGeneratesImage() {
        let image = renderFixtureCard(sourceFilterDescription: "Apple Watch")

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

    /// The unfiltered case is the common one, and it must not render a "Sources:" row at all.
    @Test @MainActor func testShareRendererGeneratesImageWithoutASourceFilter() {
        let image = renderFixtureCard(sourceFilterDescription: nil)

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }
}
