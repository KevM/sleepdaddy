import SwiftUI

struct TimelineNightNavigationControls: View {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            navigationButton(
                systemName: "chevron.left",
                label: "Previous night",
                hint: "Switches to the previous night",
                isEnabled: canGoPrevious,
                action: onPrevious
            )

            Spacer()

            navigationButton(
                systemName: "chevron.right",
                label: "Next night",
                hint: "Switches to the next night",
                isEnabled: canGoNext,
                action: onNext
            )
        }
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
    }

    private func navigationButton(
        systemName: String,
        label: String,
        hint: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if isEnabled {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isEnabled ? .accentColor : .gray.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}
