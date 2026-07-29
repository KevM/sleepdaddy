import SwiftUI

public struct ExcludedRecordsView: View {
    let excludedIDs: Set<String>
    let excludedDetails: [String: NormalizedSleepInterval]
    let onRestore: (String) -> Void
    let onRestoreAll: () -> Void

    public init(
        excludedIDs: Set<String>,
        excludedDetails: [String: NormalizedSleepInterval],
        onRestore: @escaping (String) -> Void,
        onRestoreAll: @escaping () -> Void
    ) {
        self.excludedIDs = excludedIDs
        self.excludedDetails = excludedDetails
        self.onRestore = onRestore
        self.onRestoreAll = onRestoreAll
    }

    public var body: some View {
        List {
            if excludedIDs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 44))
                        .foregroundColor(.green)
                    Text("No Excluded Records")
                        .font(.headline)
                    Text("Excluded HealthKit records will appear here. They are hidden from timeline calculations locally in SleepDaddy without modifying HealthKit.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(Array(excludedIDs).sorted(), id: \.self) { sampleID in
                        HStack(alignment: .top) {
                            if let detail = excludedDetails[sampleID] {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(detail.stage.themeColor)
                                            .frame(width: 8, height: 8)
                                        Text(detail.stage.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                        Spacer()
                                        Text(detail.sourceName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Text("\(formattedDate(detail.startDate)), \(AccessibilityHelpers.formattedTimeRange(start: detail.startDate, end: detail.endDate))")
                                        .font(.footnote)
                                        .foregroundColor(.primary)

                                    Text("ID: \(sampleID)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fontDesign(.monospaced)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Excluded Record")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("ID: \(sampleID)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .fontDesign(.monospaced)
                                }
                            }

                            Spacer()

                            Button("Restore") {
                                onRestore(sampleID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button("Restore All Exclusions", role: .destructive, action: onRestoreAll)
                }
            }
        }
        .navigationTitle("Excluded Records")
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
