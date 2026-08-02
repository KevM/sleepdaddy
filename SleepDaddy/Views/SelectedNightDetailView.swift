import SwiftUI

public struct SelectedNightDetailView: View {
    @Bindable var model: NightBrowserModel
    let layoutMode: SelectedNightLayoutMode
    let dateRange: ClosedRange<Date>?
    @State private var viewportPresentation = TimelineViewportPresentation()

    public init(model: NightBrowserModel) {
        self.model = model
        self.layoutMode = .standard
        self.dateRange = nil
    }

    init(
        model: NightBrowserModel,
        layoutMode: SelectedNightLayoutMode,
        dateRange: ClosedRange<Date>?
    ) {
        self.model = model
        self.layoutMode = layoutMode
        self.dateRange = dateRange
    }

    nonisolated static func immersiveTimelineHeight(
        availableHeight: CGFloat,
        navigatorHeight: CGFloat
    ) -> CGFloat {
        max(220, availableHeight - navigatorHeight - 6)
    }

    public var body: some View {
        Group {
            switch layoutMode {
            case .standard:
                standardDetail
            case .immersiveLandscape:
                immersiveDetail
            }
        }
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
        .onChange(of: model.selectedAssembledNight?.id) { _, _ in
            viewportPresentation.clearLiveViewport()
        }
        .onDisappear {
            viewportPresentation.clearLiveViewport()
        }
    }

    @ViewBuilder
    private var standardDetail: some View {
        VStack(spacing: 12) {
            if let night = model.selectedAssembledNight {
                if night.hasSleepData {
                    // Detailed Zoomable Timeline Canvas
                    timelineCanvas(night: night)

                    // Slim Context Navigator
                    contextNavigator(night: night)
                } else {
                    emptyNightState
                }
            } else {
                ProgressView("Loading night...")
                    .frame(height: 240)
            }
        }
    }

    @ViewBuilder
    private var immersiveDetail: some View {
        if let night = model.selectedAssembledNight {
            if night.hasSleepData {
                GeometryReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            timelineCanvas(night: night)
                                .frame(height: Self.immersiveTimelineHeight(
                                    availableHeight: proxy.size.height,
                                    navigatorHeight: 64
                                ))
                                .overlay(alignment: .top) {
                                    NightHeaderView(
                                        night: night,
                                        canGoPrevious: model.canSelectPreviousNight,
                                        canGoNext: model.canSelectNextNight,
                                        dateRange: dateRange,
                                        presentation: .timelineOverlay,
                                        onPrevious: model.selectPreviousNight,
                                        onNext: model.selectNextNight,
                                        onSelectDate: model.selectNight
                                    )
                                    .padding(.horizontal, 84)
                                    .padding(.top, 4)
                                }

                            contextNavigator(night: night)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                VStack(spacing: 12) {
                    NightHeaderView(
                        night: night,
                        canGoPrevious: model.canSelectPreviousNight,
                        canGoNext: model.canSelectNextNight,
                        dateRange: dateRange,
                        onPrevious: model.selectPreviousNight,
                        onNext: model.selectNextNight,
                        onSelectDate: model.selectNight
                    )

                    emptyNightState
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView("Loading night...")
                    .frame(height: 240)
            }
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
    }

    private func contextNavigator(night: AssembledNight) -> some View {
        let committedViewport = TimelineViewport(
            normalizing: model.viewportStart,
            end: model.viewportEnd
        )
        let displayedViewport = viewportPresentation.displayedViewport(
            committed: committedViewport
        )

        return SlimContextNavigator(
            night: night,
            viewportStart: displayedViewport.start,
            viewportEnd: displayedViewport.end,
            onUpdateViewport: { newViewport in
                model.updateViewport(start: newViewport.start, end: newViewport.end)
            }
        )
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
