import SwiftUI

public struct NightHeaderView: View {
    public enum Presentation: Equatable, Sendable {
        case standalone
        case timelineOverlay
    }

    let night: AssembledNight
    let canGoPrevious: Bool
    let canGoNext: Bool
    let dateRange: ClosedRange<Date>?
    let presentation: Presentation
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
        presentation: Presentation = .standalone,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onSelectDate: @escaping (Date) -> Void
    ) {
        self.night = night
        self.canGoPrevious = canGoPrevious
        self.canGoNext = canGoNext
        self.dateRange = dateRange
        self.presentation = presentation
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

    @ViewBuilder
    private var datePickerContent: some View {
        let selection = Binding(
            get: { night.date },
            set: { newDate in
                onSelectDate(newDate)
                showingDatePicker = false
            }
        )
        if let range = dateRange {
            DatePicker("Select Date", selection: selection, in: range, displayedComponents: [.date])
        } else {
            DatePicker("Select Date", selection: selection, displayedComponents: [.date])
        }
    }

    @ViewBuilder
    private var headerContent: some View {
        HStack(spacing: 8) {
            Button(action: {
                if canGoPrevious {
                    onPrevious()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(canGoPrevious ? .accentColor : .gray.opacity(0.4))
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
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    Text(durationFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(night.hasSleepData ? .accentColor : .secondary)
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
                    .foregroundColor(canGoNext ? .accentColor : .gray.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoNext)
            .accessibilityLabel("Next night")
            .accessibilityHint("Switches to the next night")
        }
    }

    public var body: some View {
        Group {
            switch presentation {
            case .standalone:
                headerContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.systemBackground))
            case .timelineOverlay:
                headerContent
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
        }
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
        .preference(
            key: NightHeaderPresentationPreferenceKey.self,
            value: presentation
        )
        .anchorPreference(
            key: NightHeaderBoundsPreferenceKey.self,
            value: .bounds,
            transform: { $0 }
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

struct NightHeaderPresentationPreferenceKey: PreferenceKey {
    static let defaultValue: NightHeaderView.Presentation? = nil

    static func reduce(
        value: inout NightHeaderView.Presentation?,
        nextValue: () -> NightHeaderView.Presentation?
    ) {
        value = nextValue() ?? value
    }
}

struct NightHeaderBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    ) {
        value = nextValue() ?? value
    }
}
