import SwiftUI

struct LandscapeNightToolbarSemanticElement: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case datePicker
        case duration
    }

    let role: Role
    let accessibilityLabel: String
    let accessibilityHint: String?
    let isInteractive: Bool
}

struct LandscapeNightToolbarSemanticElementsPreferenceKey: PreferenceKey {
    static let defaultValue: [LandscapeNightToolbarSemanticElement] = []

    static func reduce(
        value: inout [LandscapeNightToolbarSemanticElement],
        nextValue: () -> [LandscapeNightToolbarSemanticElement]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct LandscapeNightToolbarPresencePreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct LandscapeNightToolbarView: View {
    let night: AssembledNight
    let dateRange: ClosedRange<Date>?
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

    private var dateSemanticElement: LandscapeNightToolbarSemanticElement {
        LandscapeNightToolbarSemanticElement(
            role: .datePicker,
            accessibilityLabel: formattedDate,
            accessibilityHint: "Double tap to choose a date.",
            isInteractive: true
        )
    }

    private var durationSemanticElement: LandscapeNightToolbarSemanticElement {
        LandscapeNightToolbarSemanticElement(
            role: .duration,
            accessibilityLabel: "Sleep duration, \(formattedDuration)",
            accessibilityHint: nil,
            isInteractive: false
        )
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
            Button {
                showingDatePicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(formattedDate)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .layoutPriority(1)
            .accessibilityLabel(dateSemanticElement.accessibilityLabel)
            .accessibilityHint(dateSemanticElement.accessibilityHint ?? "")
            .preference(
                key: LandscapeNightToolbarSemanticElementsPreferenceKey.self,
                value: [dateSemanticElement]
            )

            Text(formattedDuration)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(durationSemanticElement.accessibilityLabel)
                .preference(
                    key: LandscapeNightToolbarSemanticElementsPreferenceKey.self,
                    value: [durationSemanticElement]
                )
        }
        .preference(
            key: LandscapeNightToolbarPresencePreferenceKey.self,
            value: true
        )
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
}
