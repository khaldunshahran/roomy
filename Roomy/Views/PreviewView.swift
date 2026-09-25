import SwiftUI

/// Before/after preview of the compression on a representative photo.
struct PreviewView: View {
    @EnvironmentObject var appState: AppState

    @State private var representative: LibraryItem?
    @State private var representativeVideo: LibraryItem?
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var originalBytes: Int64 = 0
    @State private var compressedBytes: Int64 = 0
    @State private var resultFormat = ""
    @State private var isLoading = true
    @State private var loadError: String?

    private var hasHDR: Bool {
        appState.selectedItems.contains(where: \.isHDR)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Preview")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(appState.selectedItems.count) items · \(appState.preset.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if isLoading {
                    SwiftUI.ProgressView("Preparing preview…")
                        .padding()
                } else if let error = loadError {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else if let before = beforeImage, let after = afterImage {
                    CompareSlider(before: before, after: after)
                        .roomyCard()
                    stats
                        .roomyCard()
                } else if let video = representativeVideo {
                    videoNote(for: video)
                        .roomyCard()
                }

                if hasHDR {
                    Label("HDR photos may look slightly different after compression.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    let wasFirstWin = appState.isFirstWinAvailable
                    if wasFirstWin {
                        appState.markFirstWinUsed()
                    }
                    appState.lastBatchWasFirstWin = wasFirstWin
                    appState.batch.start(items: appState.selectedItems, preset: appState.preset)
                    appState.route = .progress
                } label: {
                    Text("Compress \(appState.selectedItems.count) Items")
                        .roomyPrimaryButton(isEnabled: !appState.selectedItems.isEmpty)
                }
                .disabled(appState.selectedItems.isEmpty)
                .accessibilityLabel("Compress \(appState.selectedItems.count) items")
            }
            .padding()
        }
        .task { await prepare() }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(FormatHelpers.bytes(originalBytes))
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
                Text(FormatHelpers.bytes(compressedBytes))
                    .fontWeight(.bold)
            }
            .font(.headline)

            if let rep = representative, let after = afterImage {
                Text("\(rep.pixelWidth) × \(rep.pixelHeight) px → \(Int(after.size.width)) × \(Int(after.size.height)) px")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(appState.preset.title): \(appState.preset.tagline)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !resultFormat.isEmpty {
                Text("Saves as \(resultFormat)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func videoNote(for item: LibraryItem) -> some View {
        VStack(spacing: 12) {
            AssetThumbnailView(asset: item.asset, size: CGSize(width: 200, height: 200))
            Text("Video previews show estimates — compression runs at full quality.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func prepare() async {
        let photos = appState.selectedItems.filter { !$0.isVideo }
        guard let rep = photos.max(by: { $0.originalBytes < $1.originalBytes }) else {
            representativeVideo = appState.selectedItems.first(where: \.isVideo)
            isLoading = false
            return
        }
        representative = rep
        do {
            let data = try await appState.library.requestImageData(for: rep) { _ in }
            originalBytes = Int64(data.count)
            let preset = appState.preset
            let compressed = try await Task.detached(priority: .userInitiated) {
                try await CompressionService.compressPhoto(data, preset: preset)
            }.value
            guard let before = UIImage(data: data), let after = UIImage(data: compressed.data) else {
                loadError = "Couldn't read that photo for preview."
                isLoading = false
                return
            }
            beforeImage = before
            afterImage = after
            compressedBytes = Int64(compressed.data.count)
            resultFormat = compressed.format
        } catch {
            loadError = "Couldn't prepare the preview. You can still compress — the full run handles this file properly."
        }
        isLoading = false
    }
}

/// Drag slider that wipes the "after" image over the "before" image.
struct CompareSlider: View {
    let before: UIImage
    let after: UIImage

    @State private var fraction: Double = 0.5

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Image(uiImage: before)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)

                    Image(uiImage: after)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width * fraction, height: geo.size.height, alignment: .topLeading)
                        .clipped()

                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: geo.size.width * fraction - 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 320)
            .cornerRadius(12)

            Slider(value: $fraction, in: 0...1)
                .accessibilityLabel("Before and after comparison slider")

            HStack {
                Text("Before")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("After")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
