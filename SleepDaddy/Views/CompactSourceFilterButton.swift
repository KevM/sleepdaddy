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

    private var isFilterActive: Bool {
        !selectedSourceIDs.isEmpty || hidesBriefAwakes
    }

    public var body: some View {
        Button {
            showingFilterSheet = true
        } label: {
            // The container is load-bearing: a bare Image as a Button label picks up
            // different toolbar metrics and shifts the icon ~4pt against its siblings.
            ZStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(isFilterActive ? .accentColor : .primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Filter sleep sources")
        .accessibilityValue(isFilterActive ? "Filters active" : "No filters")
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
                                            .foregroundColor(.accentColor)
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
