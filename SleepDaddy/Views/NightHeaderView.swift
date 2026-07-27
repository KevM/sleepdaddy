import SwiftUI

public struct NightHeaderView: View {
    let night: AssembledNight
    let canGoPrevious: Bool
    let canGoNext: Bool
    let dateRange: ClosedRange<Date>?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelectDate: (Date) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var showingDatePicker = false
    @State private var hasSwipedInCurrentGesture = false

    public init(
        night: AssembledNight,
        canGoPrevious: Bool,
        canGoNext: Bool,
        dateRange: ClosedRange<Date>? = nil,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSelectDate: @escaping (Date) -> Void
    ) {
        self.night = night
        self.canGoPrevious = canGoPrevious
        self.canGoNext = canGoNext
        self.dateRange = dateRange
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSelectDate = onSelectDate
    }

    static func formattedDate(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private var dateFormatted: String {
        Self.formattedDate(
            night.date,
            locale: locale,
            timeZone: timeZone
        )
    }

    private var durationFormatted: String {
        if night.hasSleepData {
            return AccessibilityHelpers.formattedTimeInterval(night.summary.totalSleepDuration)
        } else {
            return "No Data"
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if canGoPrevious {
                    onPrevious()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canGoPrevious ? .blue : .gray.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoPrevious)
            .accessibilityLabel("Previous night")
            .accessibilityHint("Switches to the previous night")

            Spacer()

            Button {
                showingDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(dateFormatted)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(durationFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(night.hasSleepData ? .blue : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .layoutPriority(1)
            .accessibilityLabel("\(dateFormatted), \(durationFormatted)")
            .accessibilityHint("Double tap to choose a date")

            Spacer()

            Button(action: {
                if canGoNext {
                    onNext()
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canGoNext ? .blue : .gray.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Next night")
            .accessibilityHint("Switches to the next night")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemBackground))
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard !hasSwipedInCurrentGesture else { return }
                    let hTranslation = value.translation.width
                    let vTranslation = value.translation.height
                    if abs(hTranslation) > 60 && abs(hTranslation) > abs(vTranslation) {
                        hasSwipedInCurrentGesture = true
                        if hTranslation < 0 {
                            if canGoNext {
                                onNext()
                            }
                        } else {
                            if canGoPrevious {
                                onPrevious()
                            }
                        }
                    }
                }
                .onEnded { _ in
                    hasSwipedInCurrentGesture = false
                }
        )
        .accessibilityAction(named: Text("Previous night")) {
            if canGoPrevious {
                onPrevious()
            }
        }
        .accessibilityAction(named: Text("Next night")) {
            if canGoNext {
                onNext()
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                VStack {
                    if let range = dateRange {
                        DatePicker(
                            "Select Date",
                            selection: Binding(
                                get: { night.date },
                                set: { newDate in
                                    onSelectDate(newDate)
                                    showingDatePicker = false
                                }
                            ),
                            in: range,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                    } else {
                        DatePicker(
                            "Select Date",
                            selection: Binding(
                                get: { night.date },
                                set: { newDate in
                                    onSelectDate(newDate)
                                    showingDatePicker = false
                                }
                            ),
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                    }
                }
                .navigationTitle("Select Night")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
