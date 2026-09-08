import SwiftUI

/// Contextual controls over the chart; opening this panel never changes its geometry.
struct VitalsEventPanel: View {
    let event: DesaturationEvent
    let position: Int
    let count: Int
    let stage: SleepStage?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("Event \(position) of \(count)")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Close event details")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.startDate, format: .dateTime.hour().minute().second())
                    Text("Lowest SpO₂ \(event.nadir)%")
                    Text(stage == .asleepUnspecified ? "Unknown" : stage?.displayName ?? "No sleep stage data")
                    Text("\(Int(event.duration.rounded())) seconds")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.top)
            .id(event.id)
            ViewThatFits(in: .horizontal) {
                navigation(showsText: true).fixedSize(horizontal: true, vertical: false)
                navigation(showsText: false)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.15))
        }
        .accessibilityElement(children: .contain)
    }

    private func navigation(showsText: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                navigationLabel("Previous", symbol: "chevron.left", showsText: showsText)
            }
            .disabled(position <= 1)
            .accessibilityLabel("Previous oxygen event")
            Button(action: onNext) {
                navigationLabel("Next", symbol: "chevron.right", showsText: showsText)
            }
            .disabled(position >= count)
            .accessibilityLabel("Next oxygen event")
        }
        .font(.body)
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func navigationLabel(_ title: String, symbol: String, showsText: Bool) -> some View {
        Group {
            if showsText {
                Label(title, systemImage: symbol)
            } else {
                Image(systemName: symbol)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}
