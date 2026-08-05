import SwiftUI
import UniformTypeIdentifiers

/// Files-picker entry point for a Checkme O2 Max CSV export.
public struct VitalsImportButton: View {
    @Bindable var model: NightBrowserModel
    @State private var isPresented = false
    @State private var errorMessage: String?

    public init(model: NightBrowserModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Import Pulse Oximeter CSV", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            Task { await handle(result) }
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handle(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    try await model.importVitals(from: url)
                } catch let error as VitalsImportError {
                    errorMessage = error.userMessage
                    return
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
        }
    }
}
