import SwiftUI

public struct SettingsView: View {
    @Binding var coreStartHour: Int
    @Binding var coreEndHour: Int
    let onDismiss: () -> Void

    public init(
        coreStartHour: Binding<Int>,
        coreEndHour: Binding<Int>,
        onDismiss: @escaping () -> Void
    ) {
        self._coreStartHour = coreStartHour
        self._coreEndHour = coreEndHour
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Core Night Window"), footer: Text("Adjacent sleep within 4 hours is included automatically.")) {
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

                Section(header: Text("About SleepDaddy")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppVersion.version())
                            .foregroundColor(.secondary)
                    }

                    if let build = AppVersion.build() {
                        HStack {
                            Text("Build")
                            Spacer()
                            Text(build)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
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
