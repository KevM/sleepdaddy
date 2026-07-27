import SwiftUI

public struct CompactSourceFilterButton: View {
    let availableSources: [String: String]
    let selectedSourceIDs: [String]
    let hidesBriefAwakes: Bool
    let onToggleSource: (String) -> Void
    let onClearFilter: () -> Void
    let onToggleHideBriefAwakes: () -> Void

    @State private var showingFilterSheet = false

    public init(
        availableSources: [String: String],
        selectedSourceIDs: [String],
        hidesBriefAwakes: Bool,
        onToggleSource: @escaping (String) -> Void,
        onClearFilter: @escaping () -> Void,
        onToggleHideBriefAwakes: @escaping () -> Void
    ) {
        self.availableSources = availableSources
        self.selectedSourceIDs = selectedSourceIDs
        self.hidesBriefAwakes = hidesBriefAwakes
        self.onToggleSource = onToggleSource
        self.onClearFilter = onClearFilter
        self.onToggleHideBriefAwakes = onToggleHideBriefAwakes
    }

    public var body: some View {
        Button {
            showingFilterSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)

                if !selectedSourceIDs.isEmpty || hidesBriefAwakes {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Filter sleep sources")
        .sheet(isPresented: $showingFilterSheet) {
            NavigationStack {
                List {
                    Section {
                        Text("When no sources are selected, sleep data from all sources is shown.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Section(
                        header: Text("Timeline Display"),
                        footer: Text("Awake periods of one minute or less are hidden from the timeline. Sleep totals are unaffected.")
                    ) {
                        Toggle("Hide Brief Awakes", isOn: Binding(
                            get: { hidesBriefAwakes },
                            set: { _ in onToggleHideBriefAwakes() }
                        ))
                        .accessibilityHint("Hides awake periods of one minute or less from the timeline drawing")
                    }

                    Section("Sources") {
                        let sortedKeys = availableSources.keys.sorted {
                            (availableSources[$0] ?? $0) < (availableSources[$1] ?? $1)
                        }

                        ForEach(sortedKeys, id: \.self) { sourceID in
                            let name = availableSources[sourceID] ?? sourceID
                            let isChecked = selectedSourceIDs.contains(sourceID)

                            Button {
                                onToggleSource(sourceID)
                            } label: {
                                HStack {
                                    Text(name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if isChecked {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                            .accessibilityLabel("Filter source \(name)")
                            .accessibilityValue(isChecked ? "Selected" : "Unselected")
                        }
                    }

                    if !selectedSourceIDs.isEmpty {
                        Section {
                            Button("Clear Filter", role: .destructive) {
                                onClearFilter()
                            }
                        }
                    }
                }
                .navigationTitle("Timeline Filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingFilterSheet = false
                        }
                    }
                }
            }
        }
    }
}
