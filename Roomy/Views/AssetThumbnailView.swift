import SwiftUI
import Photos

/// Small thumbnail for a `PHAsset`, loaded through `PHImageManager`.
/// Shows a gray placeholder until the image arrives.
struct AssetThumbnailView: View {
    let asset: PHAsset
    var size = CGSize(width: 120, height: 120)

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .cornerRadius(8)
        .accessibilityHidden(true)
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: size.width * 2, height: size.height * 2),
                contentMode: .aspectFill,
                options: options
            ) { fetched, _ in
                Task { @MainActor in
                    if let fetched {
                        self.image = fetched
                    }
                }
            }
        }
    }
}
