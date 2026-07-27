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

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SleepDaddy Timeline")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)

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

            // Legend
            HStack(spacing: 12) {
                ForEach(SleepStage.allCases, id: \.self) { stage in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(stage.themeColor)
                            .frame(width: 12, height: 12)
                        Text(stage.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
