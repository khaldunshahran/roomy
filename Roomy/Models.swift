import Foundation
import Photos

// MARK: - Quality presets

/// Compression quality preset shown on the finder/selection screens.
enum QualityPreset: String, CaseIterable, Identifiable {
    case smart
    case smaller
    case best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "Smart"
        case .smaller: return "Smaller"
        case .best: return "Best quality"
        }
    }

    var tagline: String {
        switch self {
        case .smart:
            return "Shrinks files while keeping full size. The best choice for most people."
        case .smaller:
            return "Lower resolution and stronger squeeze. Biggest savings, slightly softer."
        case .best:
            return "Gentle squeeze, keeps everything looking its best. Smaller savings."
        }
    }

    /// One-word summary for the compact preset picker.
    var shortTagline: String {
        switch self {
        case .smart: return "Balanced"
        case .smaller: return "Max savings"
        case .best: return "Top quality"
        }
    }
}

// MARK: - Photo library access

/// Simplified view of the user's photo library authorization status.
enum PhotoAccessState: Equatable {
    case notDetermined
    case limited
    case full
    case denied
}

// MARK: - Library items

/// A single photo or video discovered in the user's photo library.
struct LibraryItem: Identifiable {
    let id: String            // PHAsset.localIdentifier
    let asset: PHAsset
    let isVideo: Bool
    let isLivePhoto: Bool
    let isHDR: Bool
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let originalBytes: Int64
}

// MARK: - Batch processing

/// Per-item state while a compression batch is running.
enum BatchItemState: Equatable {
    case pending
    case downloadingFromICloud(progress: Double)
    case encoding(progress: Double)
    case verifying
    case saving
    case done(bytesSaved: Int64, note: String?)
    case failed(reason: String)
    case cancelled
}

/// One library item inside a running (or finished) compression batch.
struct BatchItem: Identifiable {
    let id: String
    let libraryItem: LibraryItem
    var state: BatchItemState
    var verifiedCopyLocalIdentifier: String?
    var originalDeleted: Bool = false

    /// True only when the item compressed successfully and the compressed copy
    /// has been verified in the library, so it is safe to offer deleting the original.
    var canOfferDelete: Bool {
        if case .done = state {
            return verifiedCopyLocalIdentifier != nil && !originalDeleted
        }
        return false
    }

    /// Bytes saved by this item, or 0 if it did not complete successfully.
    var bytesSaved: Int64 {
        if case .done(let saved, _) = state {
            return saved
        }
        return 0
    }

    var isFailed: Bool {
        if case .failed = state {
            return true
        }
        return false
    }
}
