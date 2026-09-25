import SwiftUI
import Photos
import AVKit

/// Full preview of the verified compressed copy, so the user can judge
/// quality before deciding what happens to the original.
struct CompressedPreviewSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: BatchItem

    @State private var previewImage: UIImage?
    @State private var previewVideoURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    SwiftUI.ProgressView("Loading preview…")
                } else if let url = previewVideoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .accessibilityLabel("Compressed video preview")
                } else if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel("Compressed photo preview")
                } else {
                    Text(loadError ?? "Couldn't load the preview.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .navigationTitle("Compressed copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let copyID = item.verifiedCopyLocalIdentifier,
              let asset = PhotoLibraryService.fetchAsset(localIdentifier: copyID) else {
            loadError = "Couldn't find the compressed copy in your library."
            isLoading = false
            return
        }
        do {
            if item.libraryItem.isVideo {
                previewVideoURL = try await appState.library.requestVideoFile(for: asset) { _ in }
            } else {
                let data = try await appState.library.requestImageData(for: asset) { _ in }
                previewImage = UIImage(data: data)
            }
        } catch {
            loadError = "Couldn't load the preview. The compressed copy is still safe in your library."
        }
        isLoading = false
    }
}
