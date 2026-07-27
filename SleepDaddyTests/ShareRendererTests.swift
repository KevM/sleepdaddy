import Testing
import Foundation
import UIKit
@testable import SleepDaddy

struct ShareRendererTests {
    @Test @MainActor func testShareRendererGeneratesImage() {
        let fixtureStore = FixtureSleepStore()
        let assembler = NightAssembler()
        let sampleDate = Date()
        let sampleIntervals = FixtureSleepStore.generateDefaultFixtures(from: sampleDate.addingTimeInterval(-86400), to: sampleDate.addingTimeInterval(86400))

        let assembled = assembler.assembleNight(
            for: sampleDate,
            allNormalizedIntervals: sampleIntervals,
            preferences: .default
        )

        let renderer = SleepShareRenderer()
        let image = renderer.renderShareImage(
            night: assembled,
            viewportStart: assembled.detectedStart,
            viewportEnd: assembled.detectedEnd,
            sourceFilterDescription: "Apple Watch"
        )

        #expect(image != nil)
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }
}
