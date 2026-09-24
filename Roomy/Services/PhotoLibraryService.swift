// PhotoLibraryService.swift
// Roomy — iPhone photo/video compressor
//
// All reads and writes go through the system Photos library. Deletion is only
// ever requested via PHAssetChangeRequest.deleteAssets, which moves the asset
// to Recently Deleted (recoverable by the user for 30 days). Every saved copy
// is verified visible in Photos before its identifier is returned.

import Foundation
import Photos
import PhotosUI
import UIKit
import AVFoundation

// MARK: - Errors

enum RoomyError: Error, LocalizedError {
    case downloadCancelled
    case saveNotConfirmed
    case noVideoTrack
    case exportFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadCancelled:
            return "The download was stopped before it finished. Please try again."
        case .saveNotConfirmed:
            return "Roomy couldn't find the saved copy in your photo library afterwards, so it isn't counting it as saved. Nothing was deleted. Please try saving again."
        case .noVideoTrack:
            return "Roomy couldn't read this video. The file may be damaged or not fully downloaded yet."
        case .exportFailed(let detail):
            return "The file couldn't be prepared. \(detail)"
        case .verificationFailed(let detail):
            return "Roomy couldn't check the result. \(detail)"
        }
    }
}

// MARK: - Thread-safe box for the async performChanges placeholder pattern

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - PhotoLibraryService

@MainActor
final class PhotoLibraryService: ObservableObject {

    @Published private(set) var accessState: PhotoAccessState = .notDetermined

    // MARK: - Authorization

    func refreshAccessState() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized:
            accessState = .full
        case .limited:
            accessState = .limited
        case .denied, .restricted:
            accessState = .denied
        case .notDetermined:
            accessState = .notDetermined
        @unknown default:
            accessState = .denied
        }
    }

    func requestAccess() async -> PhotoAccessState {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshAccessState()
        return accessState
    }

    /// Shows the system "Select Photos…" picker when access is limited.
    /// Must be called from the main thread with a visible view controller.
    nonisolated func presentLimitedLibraryPicker() {
        DispatchQueue.main.async {
            guard
                let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                let window = scene.windows.first(where: { $0.isKeyWindow }),
                let rootViewController = window.rootViewController
            else { return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
        }
    }

    // MARK: - Size measurement (private, encapsulated here)

    /// Sums the private `fileSize` of every PHAssetResource of the asset.
    private func sizeOfAsset(_ asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset)
            .reduce(0) { partial, resource in
                partial + ((resource.value(forKey: "fileSize") as? Int64) ?? 0)
            }
    }

    // MARK: - Fetching

    /// The largest photos and videos in the library, biggest first.
    /// Works with both full and limited library access.
    func fetchLargestAssets(limit: Int = 150) async -> [LibraryItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "(mediaType == %d) OR (mediaType == %d)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let fetchResult = PHAsset.fetchAssets(with: options)
        var items: [LibraryItem] = []
        items.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            items.append(LibraryItem(
                id: asset.localIdentifier,
                asset: asset,
                isVideo: asset.mediaType == .video,
                isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
                isHDR: asset.mediaSubtypes.contains(.photoHDR),
                duration: asset.duration,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                originalBytes: self.sizeOfAsset(asset)
            ))
        }
        items.sort { $0.originalBytes > $1.originalBytes }
        return Array(items.prefix(limit))
    }

    // MARK: - Downloading source data

    /// Requests the current (edited) image data for a photo.
    /// iCloud items are downloaded by iOS itself (airplane-mode friendly:
    /// the request simply waits/fails instead of crashing); progress is reported 0...1 on the main thread.
    func requestImageData(for item: LibraryItem, progress: @escaping (Double) -> Void) async throws -> Data {
        let report: @Sendable (Double) -> Void = { value in
            DispatchQueue.main.async { progress(value) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            options.progressHandler = { value, _ in report(value) }

            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(
                for: item.asset,
                options: options
            ) { data, _, _, info in
                guard !resumed else { return }
                // Ignore intermediate degraded deliveries; only the final one resumes.
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                resumed = true

                if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: RoomyError.downloadCancelled)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: RoomyError.downloadCancelled)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    /// Requests the video asset's local file URL. Even for iCloud videos this
    /// is a real on-disk file once downloaded (iOS handles the download).
    func requestVideoFile(for item: LibraryItem, progress: @escaping (Double) -> Void) async throws -> URL {
        let report: @Sendable (Double) -> Void = { value in
            DispatchQueue.main.async { progress(value) }
        }
        let avAsset: AVAsset = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.progressHandler = { value, _ in report(value) }

            var resumed = false
            PHImageManager.default().requestAVAsset(
                forVideo: item.asset,
                options: options
            ) { asset, _, info in
                guard !resumed else { return }
                resumed = true

                if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: RoomyError.downloadCancelled)
                    return
                }
                guard let asset else {
                    continuation.resume(throwing: RoomyError.noVideoTrack)
                    return
                }
                continuation.resume(returning: asset)
            }
        }
        guard let urlAsset = avAsset as? AVURLAsset else {
            throw RoomyError.noVideoTrack
        }
        return urlAsset.url
    }

    /// Downloads both parts of a Live Photo: the still image and its paired video.
    /// Progress is combined 0...1 on the main thread (image = first half, video = second half).
    func requestLivePhotoPair(for item: LibraryItem, progress: @escaping (Double) -> Void) async throws -> (imageData: Data, videoURL: URL) {
        let resources = PHAssetResource.assetResources(for: item.asset)
        guard
            let photoResource = resources.first(where: { $0.type == .photo }),
            let videoResource = resources.first(where: { $0.type == .pairedVideo })
        else {
            throw RoomyError.downloadCancelled
        }

        let report: @Sendable (Double) -> Void = { value in
            DispatchQueue.main.async { progress(value) }
        }

        async let imageData = downloadLivePhotoStill(photoResource, report: report)
        async let videoURL = downloadLivePhotoMovie(videoResource, report: report)
        return try await (imageData, videoURL)
    }

    private func downloadLivePhotoStill(_ resource: PHAssetResource, report: @Sendable @escaping (Double) -> Void) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { value in report(value * 0.5) }

            var chunks = Data()
            var resumed = false
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in chunks.append(chunk) }
            ) { error in
                guard !resumed else { return }
                resumed = true
                if error != nil || chunks.isEmpty {
                    continuation.resume(throwing: RoomyError.downloadCancelled)
                } else {
                    continuation.resume(returning: chunks)
                }
            }
        }
    }

    private func downloadLivePhotoMovie(_ resource: PHAssetResource, report: @Sendable @escaping (Double) -> Void) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            options.progressHandler = { value in report(0.5 + value * 0.5) }

            var resumed = false
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: tempURL,
                options: nil
            ) { error in
                guard !resumed else { return }
                resumed = true
                if error != nil {
                    continuation.resume(throwing: RoomyError.downloadCancelled)
                } else {
                    continuation.resume(returning: tempURL)
                }
            }
        }
    }

    // MARK: - Saving

    /// Runs the change block, then verifies the new asset is actually visible
    /// in Photos before returning its local identifier. Throws
    /// `RoomyError.saveNotConfirmed` if verification fails.
    private func performSave(_ changes: @escaping @Sendable () -> String?) async throws -> String {
        let idBox = Box<String?>(nil)
        try await PHPhotoLibrary.shared().performChanges {
            idBox.value = changes()
        }
        guard
            let identifier = idBox.value,
            PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).count > 0
        else {
            throw RoomyError.saveNotConfirmed
        }
        return identifier
    }

    /// Saves a compressed photo as a new asset, keeping creation date (and location if asked).
    func savePhotoCopy(_ data: Data, original: PHAsset, keepLocation: Bool) async throws -> String {
        try await performSave {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
            request.creationDate = original.creationDate
            if keepLocation {
                request.location = original.location
            }
            return request.placeholderForCreatedAsset?.localIdentifier
        }
    }

    /// Saves a compressed video as a new asset, keeping creation date (and location if asked).
    func saveVideoCopy(_ fileURL: URL, original: PHAsset, keepLocation: Bool) async throws -> String {
        try await performSave {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: fileURL, options: nil)
            request.creationDate = original.creationDate
            if keepLocation {
                request.location = original.location
            }
            return request.placeholderForCreatedAsset?.localIdentifier
        }
    }

    /// Saves a Live Photo as a new asset (still image + paired video),
    /// keeping creation date (and location if asked).
    func saveLivePhotoCopy(imageData: Data, videoURL: URL, original: PHAsset, keepLocation: Bool) async throws -> String {
        try await performSave {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
            request.creationDate = original.creationDate
            if keepLocation {
                request.location = original.location
            }
            return request.placeholderForCreatedAsset?.localIdentifier
        }
    }

    // MARK: - Deletion

    /// Moves the original to Recently Deleted via PHAssetChangeRequest.deleteAssets.
    /// iOS keeps it recoverable for 30 days — nothing is permanently erased here.
    func moveToRecentlyDeleted(_ asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
        }
    }

    // MARK: - Quick estimate (nonisolated)

    /// Sums the file sizes of the largest `limit` assets without touching actor state.
    /// Returns nil when photo access hasn't been granted (denied or not determined).
    nonisolated static func quickTopItemsEstimate(limit: Int = 50) async -> Int64? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "(mediaType == %d) OR (mediaType == %d)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let fetchResult = PHAsset.fetchAssets(with: options)
        var sizes: [Int64] = []
        sizes.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            let total = PHAssetResource.assetResources(for: asset)
                .reduce(Int64(0)) { partial, resource in
                    partial + ((resource.value(forKey: "fileSize") as? Int64) ?? 0)
                }
            sizes.append(total)
        }
        sizes.sort(by: >)
        return sizes.prefix(limit).reduce(0, +)
    }
}
