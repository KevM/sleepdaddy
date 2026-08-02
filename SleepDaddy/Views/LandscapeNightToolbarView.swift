import SwiftUI

struct LandscapeNightToolbarView: View {
    let night: AssembledNight
    let dateRange: ClosedRange<Date>?
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectDate: (Date) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var showingDatePicker = false

    private var formattedDate: String {
        NightHeaderView.formattedDate(
            night.date,
            locale: locale,
            timeZone: timeZone
        )
    }

    private var formattedDuration: String {
        NightHeaderView.formattedDuration(for: night)
    }

    @ViewBuilder
    private var datePickerContent: some View {
        let selection = Binding(
            get: { night.date },
            set: { newDate in
                onSelectDate(newDate)
                showingDatePicker = false
            }
        )
        if let dateRange {
            DatePicker(
                "Select Date",
                selection: selection,
                in: dateRange,
                displayedComponents: [.date]
            )
        } else {
            DatePicker(
                "Select Date",
                selection: selection,
                displayedComponents: [.date]
            )
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                navigationButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Previous night",
                    accessibilityHint: "Switches to the previous night",
                    isEnabled: canGoPrevious,
                    action: onPrevious
                )

                Button {
                    showingDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(formattedDate)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .layoutPriority(1)
                .accessibilityLabel(formattedDate)
                .accessibilityHint("Double tap to choose a date")

                navigationButton(
                    systemName: "chevron.right",
                    accessibilityLabel: "Next night",
                    accessibilityHint: "Switches to the next night",
                    isEnabled: canGoNext,
                    action: onNext
                )
            }

            Text(formattedDuration)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep duration, \(formattedDuration)")
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                datePickerContent
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select Night")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private func navigationButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
