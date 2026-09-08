import SwiftUI
import UniformTypeIdentifiers

/// Files-picker entry point for a Checkme O2 Max CSV export.
public struct VitalsImportButton: View {
    @Bindable var model: NightBrowserModel
    @State private var isPresented = false
    @State private var errorMessage: String?

    /// Content types allowed in the file importer.
    ///
    /// Accepts `.commaSeparatedText`, `.plainText`, `.text`, `.data`, and UTTypes for `.csv`
    /// files so that files tagged with generic text/data UTIs by Files app, cloud storage,
    /// AirDrop, or email remain selectable.
    public static var allowedContentTypes: [UTType] {
        var types: [UTType] = [
            .commaSeparatedText,
            .plainText,
            .text,
            .data
        ]
        if let csvExtensionType = UTType(filenameExtension: "csv"), !types.contains(csvExtensionType) {
            types.append(csvExtensionType)
        }
        if let csvMimeType = UTType(mimeType: "text/csv"), !types.contains(csvMimeType) {
            types.append(csvMimeType)
        }
        return types
    }

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
            allowedContentTypes: Self.allowedContentTypes,
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
