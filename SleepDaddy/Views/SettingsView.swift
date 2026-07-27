import SwiftUI

public struct SettingsView: View {
    @Binding var coreStartHour: Int
    @Binding var coreEndHour: Int
    let excludedIDs: Set<String>
    let excludedDetails: [String: NormalizedSleepInterval]
    let onRestoreExclusion: (String) -> Void
    let onRestoreAllExclusions: () -> Void
    let onDismiss: () -> Void

    public init(
        coreStartHour: Binding<Int>,
        coreEndHour: Binding<Int>,
        excludedIDs: Set<String>,
        excludedDetails: [String: NormalizedSleepInterval],
        onRestoreExclusion: @escaping (String) -> Void,
        onRestoreAllExclusions: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._coreStartHour = coreStartHour
        self._coreEndHour = coreEndHour
        self.excludedIDs = excludedIDs
        self.excludedDetails = excludedDetails
        self.onRestoreExclusion = onRestoreExclusion
        self.onRestoreAllExclusions = onRestoreAllExclusions
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Core Night Window"), footer: Text("The core window is the seed period for grouping nightly sleep. Contiguous sleep before or after will be adaptively included up to 4 hours.")) {
                    Picker("Window Start Hour", selection: $coreStartHour) {
                        ForEach(12...23, id: \.self) { hour in
                            Text(hourString(hour)).tag(hour)
                        }
                    }

                    Picker("Window End Hour", selection: $coreEndHour) {
                        ForEach(4...12, id: \.self) { hour in
                            Text(hourString(hour)).tag(hour)
                        }
                    }
                }

                Section(header: Text("Local Preferences")) {
                    NavigationLink {
                        ExcludedRecordsView(
                            excludedIDs: excludedIDs,
                            excludedDetails: excludedDetails,
                            onRestore: onRestoreExclusion,
                            onRestoreAll: onRestoreAllExclusions
                        )
                    } label: {
                        HStack {
                            Text("Excluded Records")
                            Spacer()
                            Text("\(excludedIDs.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("About SleepDaddy")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0 (Local Only)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Privacy")
                        Spacer()
                        Text("Read-Only Local HealthKit")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }

    private func hourString(_ hour: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:00 a"
        let calendar = Calendar.current
        if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) {
            return f.string(from: date)
        }
        return "\(hour):00"
    }
}
