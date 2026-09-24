import Foundation
import Photos

/// Sequential batch pipeline for the Roomy compressor.
///
/// Hard guarantees:
/// - Items are processed one at a time, in order.
/// - An original is never touched until its compressed copy is verified AND
///   confirmed saved in the Photos library.
/// - Failures are per-item: one bad file never wipes completed work.
/// - `cancel()` keeps completed work: the in-flight item aborts, the
///   remaining items become `.cancelled`.
/// - Live Photo rebuild failures fall back to still-photo-only with an
///   honest note — never silently.
@MainActor
final class BatchEngine: ObservableObject {
    @Published private(set) var items: [BatchItem] = []
    @Published private(set) var isRunning = false
    /// Non-state-overwriting error surface for `deleteOriginal(_:)` failures.
    /// `.done` is left intact so `bytesSaved` is never lost.
    @Published private(set) var lastDeleteError: String?

    let library: PhotoLibraryService
    private let videoCompressor = VideoCompressor()
    private var cancelRequested = false
    private var currentPreset: QualityPreset = .smart
    private var keepLocation = false

    init(library: PhotoLibraryService) { self.library = library }

    var measuredBytesSaved: Int64 { items.reduce(0) { $0 + $1.bytesSaved } }
    var doneCount: Int { items.filter { if case .done = $0.state { return true }; return false }.count }
    var failedCount: Int { items.filter(\.isFailed).count }

    // MARK: - Batch lifecycle

    /// Starts a batch. Non-async: spawns its own task. No-op if already running.
    func start(items libraryItems: [LibraryItem], preset: QualityPreset) {
        guard !isRunning else { return }
        self.items = libraryItems.map { BatchItem(id: $0.id, libraryItem: $0, state: .pending, verifiedCopyLocalIdentifier: nil) }
        self.currentPreset = preset
        self.lastDeleteError = nil
        Task { await run() }
    }

    private func run() async {
        cancelRequested = false
        isRunning = true
        keepLocation = UserDefaults.standard.bool(forKey: "roomy.keepLocation")
        BatchStore.saveManifest(itemIDs: items.map(\.id), preset: currentPreset.rawValue)
        for index in items.indices {
            if cancelRequested {
                for j in index..<items.count where isTerminal(items[j].state) == false {
                    setState(j, .cancelled)
                }
                break
            }
            await processItem(at: index)
        }
        isRunning = false
    }

    private func isTerminal(_ s: BatchItemState) -> Bool {
        switch s {
        case .done, .failed, .cancelled: return true
        default: return false
        }
    }

    private func setState(_ index: Int, _ state: BatchItemState) {
        guard items.indices.contains(index) else { return }
        items[index].state = state
    }

    private func processItem(at index: Int) async {
        let item = items[index]
        do {
            if item.libraryItem.isVideo {
                try await processVideo(at: index)
            } else if item.libraryItem.isLivePhoto {
                try await processLivePhoto(at: index)
            } else {
                try await processPhoto(at: index, imageData: nil)
            }
        } catch is CancellationError {
            setState(index, .cancelled)
        } catch {
            setState(index, .failed(reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            cleanupTempLeftovers()
        }
    }

    // MARK: - Photos

    /// Compresses a still photo. When `imageData` is nil the original is
    /// downloaded from iCloud first (with progress), otherwise the supplied
    /// bytes are used directly (used by the Live Photo still-photo fallback).
    private func processPhoto(at index: Int, imageData: Data?) async throws {
        setState(index, .pending)
        let data: Data
        if let imageData {
            data = imageData
        } else {
            data = try await library.requestImageData(for: items[index].libraryItem) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self, self.items.indices.contains(index) else { return }
                    if p < 1.0 {
                        self.setState(index, .downloadingFromICloud(progress: p))
                    } else {
                        self.setState(index, .encoding(progress: 0))
                    }
                }
            }
        }

        setState(index, .encoding(progress: 0))
        let out = try await CompressionService.compressPhoto(data, preset: currentPreset)
        var final = out.data
        if !keepLocation {
            final = CompressionService.stripLocation(from: final)
        }

        setState(index, .verifying)
        let v = CompressionService.verifyPhoto(
            originalData: data,
            compressedData: final,
            expectSameDimensions: currentPreset != .smaller
        )
        guard v.passed else {
            throw RoomyError.verificationFailed(v.reason ?? "Verification failed.")
        }

        setState(index, .saving)
        let newID = try await library.savePhotoCopy(final, original: items[index].libraryItem.asset, keepLocation: keepLocation)
        finishDone(index, originalBytes: Int64(data.count), compressedBytes: Int64(final.count), newID: newID, note: nil)
    }

    // MARK: - Videos

    private func processVideo(at index: Int) async throws {
        setState(index, .pending)
        let url = try await library.requestVideoFile(for: items[index].libraryItem) { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self, self.items.indices.contains(index) else { return }
                if p < 1.0 {
                    self.setState(index, .downloadingFromICloud(progress: p))
                } else {
                    self.setState(index, .encoding(progress: 0))
                }
            }
        }

        setState(index, .encoding(progress: 0))
        // The progress closure may fire on a background thread; hop back to
        // the main actor before touching published state.
        let outURL = try await videoCompressor.compress(sourceURL: url, preset: currentPreset) { [weak self] p in
            Task { await self?.applyEncodingProgress(index: index, p: p) }
        }
        defer {
            // The compressed file served its purpose once saved; delete the
            // temp copy so a failed save doesn't leave garbage behind.
            try? FileManager.default.removeItem(at: outURL)
        }

        setState(index, .verifying)
        let v = await VideoCompressor.verifyVideo(originalURL: url, compressedURL: outURL)
        guard v.passed else {
            throw RoomyError.verificationFailed(v.reason ?? "Video verification failed.")
        }

        setState(index, .saving)
        let newID = try await library.saveVideoCopy(outURL, original: items[index].libraryItem.asset, keepLocation: keepLocation)
        finishDone(index, originalBytes: fileSize(of: url), compressedBytes: fileSize(of: outURL), newID: newID, note: nil)
    }

    /// Main-actor hop target for the video encoder's progress closure.
    private func applyEncodingProgress(index: Int, p: Double) {
        guard items.indices.contains(index) else { return }
        if case .encoding = items[index].state {
            setState(index, .encoding(progress: p))
        }
    }

    // MARK: - Live Photos

    /// Tries the full still+motion pair. On ANY failure, falls back to the
    /// still-photo path and marks the result with an honest note — never
    /// silently. If the still path fails too, the item is marked failed.
    private func processLivePhoto(at index: Int) async throws {
        do {
            let pair = try await library.requestLivePhotoPair(for: items[index].libraryItem) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self, self.items.indices.contains(index) else { return }
                    if p < 1.0 {
                        self.setState(index, .downloadingFromICloud(progress: p))
                    } else {
                        self.setState(index, .encoding(progress: 0))
                    }
                }
            }
            try await compressAndSaveLivePair(at: index, imageData: pair.imageData, videoURL: pair.videoURL)
        } catch is CancellationError {
            // User cancelled: propagate so processItem marks it .cancelled,
            // not "failed", and not the still fallback either.
            throw CancellationError()
        } catch {
            // Fallback: still photo only, with an honest note.
            do {
                try await processPhoto(at: index, imageData: nil)
            } catch is CancellationError {
                throw CancellationError()
            }
            // processPhoto marks .failed on throw; only stamp the note on a
            // successful still save.
            if case .done(let bytesSaved, _) = items[index].state {
                setState(index, .done(bytesSaved: bytesSaved, note: "Saved as still photo; the motion part could not be preserved."))
            }
        }
    }

    private func compressAndSaveLivePair(at index: Int, imageData: Data, videoURL: URL) async throws {
        setState(index, .encoding(progress: 0))

        // Still component.
        let photoOut = try await CompressionService.compressPhoto(imageData, preset: currentPreset)
        var finalImage = photoOut.data
        if !keepLocation {
            finalImage = CompressionService.stripLocation(from: finalImage)
        }

        // Motion component.
        let videoOutURL = try await videoCompressor.compress(sourceURL: videoURL, preset: currentPreset) { [weak self] p in
            Task { await self?.applyEncodingProgress(index: index, p: p) }
        }
        defer { try? FileManager.default.removeItem(at: videoOutURL) }

        setState(index, .verifying)
        let photoCheck = CompressionService.verifyPhoto(
            originalData: imageData,
            compressedData: finalImage,
            expectSameDimensions: currentPreset != .smaller
        )
        guard photoCheck.passed else {
            throw RoomyError.verificationFailed(photoCheck.reason ?? "Live Photo still-part verification failed.")
        }
        let videoCheck = await VideoCompressor.verifyVideo(originalURL: videoURL, compressedURL: videoOutURL)
        guard videoCheck.passed else {
            throw RoomyError.verificationFailed(videoCheck.reason ?? "Live Photo motion-part verification failed.")
        }

        setState(index, .saving)
        let newID = try await library.saveLivePhotoCopy(
            imageData: finalImage,
            videoURL: videoOutURL,
            original: items[index].libraryItem.asset,
            keepLocation: keepLocation
        )
        let originalBytes = Int64(imageData.count) + fileSize(of: videoURL)
        let compressedBytes = Int64(finalImage.count) + fileSize(of: videoOutURL)
        finishDone(index, originalBytes: originalBytes, compressedBytes: compressedBytes, newID: newID, note: nil)
    }

    // MARK: - Completion bookkeeping

    private func finishDone(_ index: Int, originalBytes: Int64, compressedBytes: Int64, newID: String, note: String?) {
        guard items.indices.contains(index) else { return }
        let saved = max(0, originalBytes - compressedBytes)
        items[index].verifiedCopyLocalIdentifier = newID
        setState(index, .done(bytesSaved: saved, note: note))
        BatchStore.recordCompleted(originalID: items[index].id, bytesSaved: saved)
    }

    // MARK: - Control

    /// Cancels the batch. Completed items are kept; the in-flight item aborts
    /// (via `videoCompressor.cancel()` for video encodes) and becomes
    /// `.cancelled`; everything still `.pending` becomes `.cancelled`.
    func cancel() {
        cancelRequested = true
        videoCompressor.cancel()
    }

    func retry(item: BatchItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), !isRunning else { return }
        setState(index, .pending)
        items[index].verifiedCopyLocalIdentifier = nil
        Task { await runSingle(index) }
    }

    private func runSingle(_ index: Int) async {
        isRunning = true
        cancelRequested = false
        keepLocation = UserDefaults.standard.bool(forKey: "roomy.keepLocation")
        await processItem(at: index)
        isRunning = false
    }

    /// Moves the original to Recently Deleted AFTER explicit user confirmation
    /// (the view shows the alert). Only offered for verified-saved copies.
    ///
    /// On failure the `.done` state is left intact — `bytesSaved` is never
    /// lost — and the error is surfaced via `lastDeleteError` for the view
    /// to display. The item stays eligible for a delete retry.
    func deleteOriginal(_ item: BatchItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              items[index].canOfferDelete else { return }
        do {
            try await library.moveToRecentlyDeleted(items[index].libraryItem.asset)
            items[index].originalDeleted = true
            lastDeleteError = nil
        } catch {
            lastDeleteError = "Couldn't move the original: \(error.localizedDescription). Your compressed copy is safe."
        }
    }

    func reset() {
        items = []
        isRunning = false
        cancelRequested = false
        lastDeleteError = nil
    }

    /// Returns true only when known free space exceeds 3x the needed bytes.
    /// Returns false when free space cannot be determined.
    func hasEnoughFreeSpace(for neededBytes: Int64) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else {
            return false
        }
        return free > neededBytes * 3
    }

    static func completedIDs() -> Set<String> { BatchStore.completedIDs() }

    // MARK: - Housekeeping

    /// Removes temp `.mp4` files older than 1 day from the temp directory.
    /// Compressed encode outputs are deleted by their own `defer` blocks;
    /// this catches anything abandoned by a crash or kill.
    private func cleanupTempLeftovers() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        guard let urls = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for url in urls where url.pathExtension.lowercased() == "mp4" {
            if let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mtime < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func fileSize(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

// MARK: - BatchStore

/// Crash-safe persistence: completed originals survive app kills.
/// (Originals are never touched mid-batch anyway; this is for resume UI and
/// for skipping already-completed items across launches.)
private enum BatchStore {
    private static func dir() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Roomy", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func manifestURL() -> URL { dir().appendingPathComponent("batch-manifest.json") }
    private static func completedURL() -> URL { dir().appendingPathComponent("completed.json") }

    /// Records which items this batch run started with (overwrites any prior
    /// manifest).
    static func saveManifest(itemIDs: [String], preset: String) {
        struct Manifest: Codable {
            let ids: [String]
            let preset: String
            let startedAt: Date
        }
        let manifest = Manifest(ids: itemIDs, preset: preset, startedAt: Date())
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL(), options: [.atomic])
    }

    /// Merges one completed original into the durable completed map
    /// `{ originalID: bytesSaved }`.
    static func recordCompleted(originalID: String, bytesSaved: Int64) {
        var dict: [String: Int64] = (try? Data(contentsOf: completedURL()))
            .flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]
        dict[originalID] = bytesSaved
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: completedURL(), options: [.atomic])
    }

    /// Original IDs already completed (survives app kills).
    static func completedIDs() -> Set<String> {
        let dict: [String: Int64]? = (try? Data(contentsOf: completedURL()))
            .flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) }
        return Set((dict ?? [:]).keys)
    }
}
