import SwiftUI

public struct IntervalInspectorSheet: View {
    let interval: NormalizedSleepInterval
    let conflicts: [TimelineConflict]
    let onDismiss: () -> Void

    public init(
        interval: NormalizedSleepInterval,
        conflicts: [TimelineConflict],
        onDismiss: @escaping () -> Void
    ) {
        self.interval = interval
        self.conflicts = conflicts
        self.onDismiss = onDismiss
    }

    private var matchingConflict: TimelineConflict? {
        conflicts.first { conflict in
            conflict.startDate < interval.endDate && conflict.endDate > interval.startDate
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Stage & Timing")) {
                    HStack {
                        Text("Stage")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(interval.stage.themeColor)
                                .frame(width: 10, height: 10)
                            Text(interval.stage.displayName)
                                .fontWeight(.semibold)
                        }
                    }

                    HStack {
                        Text("Time")
                        Spacer()
                        Text(AccessibilityHelpers.formattedTimeRange(start: interval.startDate, end: interval.endDate))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(AccessibilityHelpers.formattedTimeInterval(interval.duration))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("HealthKit Source")) {
                    HStack {
                        Text("Source Name")
                        Spacer()
                        Text(interval.sourceName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bundle Identifier")
                        Spacer()
                        Text(interval.sourceIdentifier)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let device = interval.deviceModel {
                        HStack {
                            Text("Device")
                            Spacer()
                            Text(device)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let conflict = matchingConflict {
                    Section(header: Text("Source Conflict Details")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Overlapping sources disagree on stage during this interval", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)

                            Divider()

                            ForEach(conflict.conflictingIntervals) { cItem in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(cItem.sourceName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(cItem.stage.displayName)
                                            .font(.caption)
                                            .foregroundColor(cItem.stage.themeColor)
                                    }
                                    Spacer()
                                    Text(AccessibilityHelpers.formattedTimeInterval(cItem.duration))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Interval Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}
