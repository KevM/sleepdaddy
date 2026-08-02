import SwiftUI

public struct ShareTimelineCardView: View {
    let night: AssembledNight
    /// The span the card draws *and* names, and it has to be the whole night: the headline
    /// is `summary.totalSleepDuration`, which is always the night's total. Handing this the
    /// live pan/zoom window instead puts "7h 12m asleep" above a two-hour range and a
    /// two-hour plot, with nothing on the card to explain the contradiction.
    let viewportStart: Date
    let viewportEnd: Date
    /// `nil` when the user has not filtered sources, which is the common case. The card then
    /// omits the row entirely rather than announcing "All Sources", which tells nobody
    /// anything.
    let sourceFilterDescription: String?

    // The header has to agree with the time labels the canvas draws below it, and those
    // come from the environment — reading `.current` instead puts an en_US 12-hour range
    // above a 24-hour axis.
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.calendar) private var calendar

    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        sourceFilterDescription: String?
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.sourceFilterDescription = sourceFilterDescription
    }

    /// Stages present in the night that the timeline's left axis does not already label.
    ///
    /// The axis prints Awake/REM/Core/Deep in their theme colours beside their percentages,
    /// so a chip for any of those repeats what the reader can already see. Only
    /// `.asleepUnspecified` — drawn as a band spanning REM through Deep — and `.inBed`, a
    /// background wash, go unnamed. That caps the legend at two chips.
    ///
    /// Both collections are consulted because they hold different stages: `.inBed` lives only
    /// in `rawIntervals` (which is what `SleepTimelineCanvas` filters when drawing the
    /// background band) while `.asleepUnspecified` lives in `displayLaneIntervals`.
    /// `nonisolated` because it is model math, not view work: `View` conformance would
    /// otherwise infer `@MainActor` and trap when a test calls it off the main actor.
    nonisolated static func legendStages(for night: AssembledNight) -> [SleepStage] {
        let axisLabelled = Set(SleepTimelineGeometry.defaultDisplayedStages)
        var present: Set<SleepStage> = []
        for interval in night.rawIntervals { present.insert(interval.stage) }
        for interval in night.displayLaneIntervals { present.insert(interval.stage) }

        return SleepStage.allCases.filter {
            present.contains($0) && !axisLabelled.contains($0)
        }
    }

    public var body: some View {
        let legend = Self.legendStages(for: night)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SleepDaddy")
                    .font(.caption)
                    .fontWeight(.bold)
                    // The asset resource rather than `.accentColor`: this card is drawn by
                    // ImageRenderer for export, which does not inherit the app's ambient tint.
                    .foregroundColor(.accent)

                // The headline. Percentages without a denominator are not shareable; this is
                // the one number that survives being seen for a second in a message thread.
                Text("\(AccessibilityHelpers.formattedTimeInterval(night.summary.totalSleepDuration)) asleep")
                    .font(.title)
                    .fontWeight(.bold)

                Text(
                    AccessibilityHelpers.formattedDateHeader(
                        night.date,
                        calendar: calendar,
                        locale: locale,
                        timeZone: timeZone
                    )
                    + " · "
                    + AccessibilityHelpers.formattedTimeRange(
                        start: viewportStart,
                        end: viewportEnd,
                        locale: locale,
                        timeZone: timeZone
                    )
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                if let sourceFilterDescription {
                    Text("Sources: \(sourceFilterDescription)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            SleepTimelineCanvas(
                night: night,
                viewportStart: viewportStart,
                viewportEnd: viewportEnd,
                selectedIntervalID: nil,
                chrome: .export,
                onSelectInterval: { _ in },
                onUpdateViewport: { _, _ in }
            )
            .frame(height: 240)
            .environment(\.timelineInteractionEnabled, false)

            if !legend.isEmpty {
                Divider()

                HStack(spacing: 14) {
                    ForEach(legend, id: \.self) { stage in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stage.themeColor)
                                .frame(width: 16, height: 16)
                            Text(stage.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

#if DEBUG

private func previewNight() -> AssembledNight {
    let reference = Date(timeIntervalSinceReferenceDate: 806_000_000)
    let intervals = FixtureSleepStore.generateDefaultFixtures(
        from: reference.addingTimeInterval(-86_400),
        to: reference.addingTimeInterval(86_400)
    )
    return NightAssembler().assembleNight(
        for: reference,
        allNormalizedIntervals: intervals,
        preferences: .default
    )
}

#Preview("Share card") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.detectedStart,
        viewportEnd: night.detectedEnd,
        sourceFilterDescription: nil
    )
}

#Preview("Share card, source filtered") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.detectedStart,
        viewportEnd: night.detectedEnd,
        sourceFilterDescription: "Apple Watch"
    )
}

#Preview("Share card (dark)") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.detectedStart,
        viewportEnd: night.detectedEnd,
        sourceFilterDescription: nil
    )
    .preferredColorScheme(.dark)
}

// The header packs date, year and clock range into one caption run at a fixed 540pt width.
// German abbreviates none of those as tightly as English, so it is the wrap check.
#Preview("Share card (de_DE)") {
    let night = previewNight()
    return ShareTimelineCardView(
        night: night,
        viewportStart: night.detectedStart,
        viewportEnd: night.detectedEnd,
        sourceFilterDescription: nil
    )
    .environment(\.locale, Locale(identifier: "de_DE"))
}

#endif
