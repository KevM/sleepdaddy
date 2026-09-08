import SwiftUI

struct VitalsChartKeyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Sleep background") {
                    ForEach([SleepStage.awake, .rem, .core, .deep, .asleepUnspecified], id: \.self) { stage in
                        stageEntry(stage)
                    }
                    Text("Unknown means sleep was recorded without a specific stage. Blank areas have no sleep stage data.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Vertical lines mark sleep stage changes. Tap the background to inspect a stage.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Oxygen saturation (SpO₂)") {
                    ForEach(VitalsColorZone.allCases, id: \.self) { zone in
                        entry(zone.color, zone == .warning ? "85% to below 90%" : zone.legendLabel)
                    }
                }
                Section("Pulse") {
                    entry(VitalsColorZone.pulseColor, "Pulse rate")
                }
                Section("Events") {
                    Text("Red markers show oxygen events below 90%. Tap a marker to view its details and move between events.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Chart key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func entry(_ color: Color, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 24, height: 18)
                .accessibilityHidden(true)
            Text(label).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stageEntry(_ stage: SleepStage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(stage.themeColor))
                StageBackgroundLane.drawPattern(
                    StageBackgroundSpans.pattern(for: stage),
                    in: rect,
                    context: &context,
                    color: .white.opacity(0.75),
                    spacing: 7
                )
            }
                .frame(width: 24, height: 18)
                .accessibilityHidden(true)
            Text(stage == .asleepUnspecified ? "Unknown" : stage.displayName)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}
