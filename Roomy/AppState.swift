import SwiftUI
import Combine

/// App-wide observable state. Owned by ``RoomyApp`` and injected as an
/// environment object into the whole view hierarchy.
@MainActor
final class AppState: ObservableObject {
    /// Top-level navigation destination.
    enum Route: Equatable {
        case welcome
        case access
        case finder
        case selection
        case preview
        case progress
        case result
        case paywall
        case reminderOptIn
        case main
    }

    @Published var route: Route = .welcome
    @Published var preset: QualityPreset = .smart
    @Published var finderItems: [LibraryItem] = []
    @Published var finderEstimateBytes: Int64 = 0
    @Published var selectedItems: [LibraryItem] = []
    @Published var lastResultBytesSaved: Int64 = 0
    @Published var lastResultItemCount: Int = 0
    @Published var lastBatchWasFirstWin = false
    @Published var remainingEstimateBytes: Int64 = 0

    /// Library scan lifecycle. The scan is slow on large libraries, so it
    /// runs once in the background (at launch when access already exists,
    /// or right after access is granted) and every screen reuses the cache.
    enum LibraryScanState: Equatable {
        case idle
        case scanning
        case ready
    }

    @Published var libraryScanState: LibraryScanState = .idle
    @Published var libraryScanProgress: Double = 0
    private var scanTask: Task<Void, Never>?

    let library: PhotoLibraryService
    let batch: BatchEngine
    let store: StoreManager

    private var cancellables = Set<AnyCancellable>()

    init() {
        let library = PhotoLibraryService()
        self.library = library
        self.batch = BatchEngine(library: library)
        self.store = StoreManager()
        // Forward nested observable changes so views observing AppState
        // refresh when library/batch/store publish.
        for publisher in [library.objectWillChange, batch.objectWillChange, store.objectWillChange] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    /// The "first win" (free compression of up to ``Config/FirstWin/maxItems``
    /// items) is available until the user unlocks the paid tier or has
    /// already used it.
    var isFirstWinAvailable: Bool {
        !store.isUnlocked && !UserDefaults.standard.bool(forKey: "roomy.firstWinUsed")
    }

    /// Persist that the free first-win batch has been used.
    func markFirstWinUsed() {
        UserDefaults.standard.set(true, forKey: "roomy.firstWinUsed")
    }

    /// Return to the main screen and clear any in-progress selection.
    func resetToMain() {
        selectedItems = []
        route = .main
    }

    // MARK: - Library scan

    /// Called once at app launch. If photo access was already granted, the
    /// library scan starts immediately in the background.
    func initialLibraryCheck() {
        library.refreshAccessState()
        if library.accessState == .full || library.accessState == .limited {
            startLibraryScanIfNeeded()
        }
    }

    /// Starts the library scan in the background unless one already ran or
    /// is running. Safe to call from anywhere, any number of times.
    func startLibraryScanIfNeeded() {
        guard libraryScanState == .idle else { return }
        runScan()
    }

    /// Re-runs the scan (manual refresh). The old results stay visible until
    /// the new ones land.
    func rescanLibrary() {
        scanTask?.cancel()
        runScan()
    }

    private func runScan() {
        libraryScanState = .scanning
        libraryScanProgress = 0
        scanTask = Task {
            // fetchLargestAssets is nonisolated: the heavy enumeration runs
            // off the main thread while this task suspends.
            let items = await library.fetchLargestAssets(limit: 60) { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.libraryScanProgress = p
                }
            }
            guard !Task.isCancelled else { return }
            self.applyScanResult(items)
        }
    }

    private func applyScanResult(_ items: [LibraryItem]) {
        finderItems = items
        let topBytes = items.prefix(40).reduce(Int64(0)) { $0 + $1.originalBytes }
        finderEstimateBytes = Int64(Double(topBytes) * Config.Estimate.smartRatio)
        libraryScanState = .ready
    }
}
