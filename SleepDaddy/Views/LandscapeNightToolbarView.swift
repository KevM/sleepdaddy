import SwiftUI

struct LandscapeNightToolbarNavigationSemantics: Equatable, Sendable {
    let label: String
    let hint: String
    let isEnabled: Bool
}

struct LandscapeNightToolbarTextSemantics: Equatable, Sendable {
    let label: String
}

enum LandscapeNightToolbarSemantics {
    static func previous(isEnabled: Bool) -> LandscapeNightToolbarNavigationSemantics {
        navigation(label: "Previous night", isEnabled: isEnabled)
    }

    static func next(isEnabled: Bool) -> LandscapeNightToolbarNavigationSemantics {
        navigation(label: "Next night", isEnabled: isEnabled)
    }

    static func date(label: String) -> LandscapeNightToolbarNavigationSemantics {
        LandscapeNightToolbarNavigationSemantics(
            label: label,
            hint: "Double tap to choose a date",
            isEnabled: true
        )
    }

    static func duration(value: String) -> LandscapeNightToolbarTextSemantics {
        LandscapeNightToolbarTextSemantics(label: "Sleep duration, \(value)")
    }

    private static func navigation(
        label: String,
        isEnabled: Bool
    ) -> LandscapeNightToolbarNavigationSemantics {
        LandscapeNightToolbarNavigationSemantics(
            label: label,
            hint: "Switches to the \(label.lowercased())",
            isEnabled: isEnabled
        )
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
        let previousSemantics = LandscapeNightToolbarSemantics.previous(
            isEnabled: canGoPrevious
        )
        let nextSemantics = LandscapeNightToolbarSemantics.next(
            isEnabled: canGoNext
        )
        let dateSemantics = LandscapeNightToolbarSemantics.date(label: formattedDate)
        let durationSemantics = LandscapeNightToolbarSemantics.duration(
            value: formattedDuration
        )

        HStack(spacing: 8) {
            HStack(spacing: 0) {
                navigationButton(
                    systemName: "chevron.left",
                    semantics: previousSemantics,
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
                .accessibilityLabel(dateSemantics.label)
                .accessibilityHint(dateSemantics.hint)

                navigationButton(
                    systemName: "chevron.right",
                    semantics: nextSemantics,
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
                .accessibilityLabel(durationSemantics.label)
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
        semantics: LandscapeNightToolbarNavigationSemantics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!semantics.isEnabled)
        .accessibilityLabel(semantics.label)
        .accessibilityHint(semantics.hint)
    }
}
