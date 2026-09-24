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
        for nested in [library as ObservableObject, batch, store] {
            nested.objectWillChange
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
}
