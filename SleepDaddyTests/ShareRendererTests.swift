import Testing
import Foundation
import UIKit
@testable import SleepDaddy

struct ShareRendererTests {
    /// Fixed rather than `Date()`: a wall-clock fixture makes the whole suite's share
    /// coverage depend on what time it is run.
    private static let reference = Date(timeIntervalSinceReferenceDate: 806_000_000)

    @MainActor
    private func render(
        night: AssembledNight,
        sourceFilterDescription: String?
    ) -> UIImage? {
        SleepShareRenderer().renderShareImage(
            night: night,
            viewportStart: night.detectedStart,
            viewportEnd: night.detectedEnd,
            sourceFilterDescription: sourceFilterDescription
        )
    }

    @MainActor
    private func renderFixtureCard(sourceFilterDescription: String?) -> UIImage? {
        let sampleIntervals = FixtureSleepStore.generateDefaultFixtures(
            from: Self.reference.addingTimeInterval(-86400),
            to: Self.reference.addingTimeInterval(86400)
        )

        let assembled = NightAssembler().assembleNight(
            for: Self.reference,
            allNormalizedIntervals: sampleIntervals,
            preferences: .default
        )

        return render(night: assembled, sourceFilterDescription: sourceFilterDescription)
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

    /// The card is a fixed 540pt wide and sizes its height to content, so a row that renders
    /// makes it taller. That is checkable without a reference image — and asserting only that
    /// an image came back would pass just as well if the row were still there.
    @Test @MainActor func theSourceRowIsAbsentWhenNothingIsFiltered() throws {
        let filtered = try #require(renderFixtureCard(sourceFilterDescription: "Apple Watch"))
        let unfiltered = try #require(renderFixtureCard(sourceFilterDescription: nil))

        #expect(unfiltered.size.width == filtered.size.width)
        #expect(unfiltered.size.height < filtered.size.height)
    }

    @Test @MainActor func theLegendBlockIsAbsentWhenTheAxisLabelsEveryStage() throws {
        let withoutLegend = try #require(
            render(
                night: ShareCardFixtures.night(with: [.awake, .rem, .core, .deep]),
                sourceFilterDescription: nil
            )
        )
        let withLegend = try #require(
            render(
                night: ShareCardFixtures.night(with: [.core, .inBed]),
                sourceFilterDescription: nil
            )
        )

        #expect(withoutLegend.size.height < withLegend.size.height)
    }
}
