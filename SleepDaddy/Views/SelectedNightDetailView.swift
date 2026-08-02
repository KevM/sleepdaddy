import SwiftUI

public struct SelectedNightDetailView: View {
    @Bindable var model: NightBrowserModel

    public init(model: NightBrowserModel) {
        self.model = model
    }

    public var body: some View {
        detail
        .sheet(item: $model.selectedInterval) { interval in
            if let night = model.selectedAssembledNight {
                IntervalInspectorSheet(
                    interval: interval,
                    conflicts: night.conflicts,
                    onDismiss: {
                        model.selectedInterval = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let night = model.selectedAssembledNight {
            if night.hasSleepData {
                timelineCanvas(night: night)
            } else {
                emptyNightState
            }
        } else {
            ProgressView("Loading night...")
                .frame(height: 240)
        }
    }

    private func timelineCanvas(night: AssembledNight) -> some View {
        SleepTimelineCanvas(
            night: night,
            viewportStart: model.viewportStart,
            viewportEnd: model.viewportEnd,
            selectedIntervalID: model.selectedInterval?.id,
            onSelectInterval: { interval in
                model.selectedInterval = interval
            },
            onUpdateViewport: { newStart, newEnd in
                model.updateViewport(start: newStart, end: newEnd)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    private var emptyNightState: some View {
        // Empty Night State
        VStack(spacing: 12) {
            Image(systemName: "moon.stars")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.6))
            Text("No eligible sleep records found for this night.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 280)
                .padding(.horizontal, 24)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }
}

// System Share Sheet Wrapper
struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
