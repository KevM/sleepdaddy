import SwiftUI

public struct ShareTimelineCardView: View {
    let night: AssembledNight
    let viewportStart: Date
    let viewportEnd: Date
    let sourceFilterDescription: String

    public init(
        night: AssembledNight,
        viewportStart: Date,
        viewportEnd: Date,
        sourceFilterDescription: String
    ) {
        self.night = night
        self.viewportStart = viewportStart
        self.viewportEnd = viewportEnd
        self.sourceFilterDescription = sourceFilterDescription
    }

    private static let legendRows: [[SleepStage]] = stride(
        from: 0,
        to: SleepStage.allCases.count,
        by: 3
    ).map { start in
        Array(SleepStage.allCases[start..<min(start + 3, SleepStage.allCases.count)])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SleepDaddy Timeline")
                        .font(.caption)
                        .fontWeight(.bold)
                        // The asset resource rather than `.accentColor`: this card is drawn by
                        // ImageRenderer for export, which does not inherit the app's ambient tint.
                        .foregroundColor(.accent)

                    Text(AccessibilityHelpers.formattedDateHeader(night.date))
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Visible Range")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(AccessibilityHelpers.formattedTimeRange(start: viewportStart, end: viewportEnd))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            Text("Sources: \(sourceFilterDescription)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            // Timeline Visualization Canvas
            SleepTimelineCanvas(
                night: night,
                viewportStart: viewportStart,
                viewportEnd: viewportEnd,
                selectedIntervalID: nil,
                onSelectInterval: { _ in },
                onUpdateViewport: { _, _ in }
            )
            .frame(height: 240)
            .environment(\.timelineInteractionEnabled, false)

            Divider()

            // Legend. Wrapped onto rows of three: at this text size the six stage
            // names no longer fit across the card's fixed 540pt width.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.legendRows, id: \.self) { row in
                    HStack(spacing: 14) {
                        ForEach(row, id: \.self) { stage in
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
