import SwiftUI

struct LandscapeNightToolbarSemanticElement: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case previousNight
        case datePicker
        case nextNight
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

    private func navigationSemanticElement(
        role: LandscapeNightToolbarSemanticElement.Role,
        label: String,
        isEnabled: Bool
    ) -> LandscapeNightToolbarSemanticElement {
        LandscapeNightToolbarSemanticElement(
            role: role,
            accessibilityLabel: label,
            accessibilityHint: "Switches to the \(label.lowercased()).",
            isInteractive: isEnabled
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
            HStack(spacing: 0) {
                navigationButton(
                    systemName: "chevron.left",
                    semanticElement: navigationSemanticElement(
                        role: .previousNight,
                        label: "Previous night",
                        isEnabled: canGoPrevious
                    ),
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

                navigationButton(
                    systemName: "chevron.right",
                    semanticElement: navigationSemanticElement(
                        role: .nextNight,
                        label: "Next night",
                        isEnabled: canGoNext
                    ),
                    action: onNext
                )
            }

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

    private func navigationButton(
        systemName: String,
        semanticElement: LandscapeNightToolbarSemanticElement,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!semanticElement.isInteractive)
        .accessibilityLabel(semanticElement.accessibilityLabel)
        .accessibilityHint(semanticElement.accessibilityHint ?? "")
        .preference(
            key: LandscapeNightToolbarSemanticElementsPreferenceKey.self,
            value: [semanticElement]
        )
    }
}
