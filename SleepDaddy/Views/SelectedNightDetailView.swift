import SwiftUI

public struct SelectedNightDetailView: View {
    @Bindable var model: NightBrowserModel
    @State private var viewportPresentation = TimelineViewportPresentation()

    public init(model: NightBrowserModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let night = model.selectedAssembledNight {
                if night.hasSleepData {
                    let committedViewport = TimelineViewport(
                        normalizing: model.viewportStart,
                        end: model.viewportEnd
                    )
                    let displayedViewport = viewportPresentation.displayedViewport(
                        committed: committedViewport
                    )

                    // Detailed Zoomable Timeline Canvas
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
                        },
                        onUpdateLiveViewport: { liveViewport in
                            if let liveViewport {
                                viewportPresentation.updateLiveViewport(liveViewport)
                            } else {
                                viewportPresentation.clearLiveViewport()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                    // Slim Context Navigator
                    SlimContextNavigator(
                        night: night,
                        viewportStart: displayedViewport.start,
                        viewportEnd: displayedViewport.end,
                        onUpdateViewport: { newViewport in
                            model.updateViewport(start: newViewport.start, end: newViewport.end)
                        }
                    )
                    .padding(.horizontal, 16)
                } else {
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
            } else {
                ProgressView("Loading night...")
                    .frame(height: 240)
            }
        }
        .sheet(item: $model.selectedInterval) { interval in
            if let night = model.selectedAssembledNight {
                IntervalInspectorSheet(
                    interval: interval,
                    conflicts: night.conflicts,
                    onExclude: { _ in
                        model.excludeSample(interval)
                    },
                    onDismiss: {
                        model.selectedInterval = nil
                    }
                )
            }
        }
        .onChange(of: model.selectedAssembledNight?.id) { _, _ in
            viewportPresentation.clearLiveViewport()
        }
        .onDisappear {
            viewportPresentation.clearLiveViewport()
        }
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
