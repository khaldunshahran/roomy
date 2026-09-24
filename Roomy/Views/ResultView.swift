import SwiftUI

/// Shows measured savings, per-item results, and the original-review step.
struct ResultView: View {
    @EnvironmentObject var appState: AppState

    @State private var pendingDelete: BatchItem?
    @State private var showDeleteAlert = false
    @State private var refreshSeed = UUID()

    private var doneItems: [BatchItem] {
        appState.batch.items.filter {
            if case .done = $0.state { return true }
            return false
        }
    }

    private var failedItems: [BatchItem] {
        appState.batch.items.filter { $0.isFailed }
    }

    private var reviewItems: [BatchItem] {
        appState.batch.items.filter { $0.canOfferDelete || $0.originalDeleted }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("You freed \(FormatHelpers.bytes(appState.lastResultBytesSaved))")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("\(appState.lastResultItemCount) items compressed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if !doneItems.isEmpty {
                    section(title: "Compressed") {
                        ForEach(doneItems) { item in
                            HStack(spacing: 12) {
                                AssetThumbnailView(asset: item.libraryItem.asset, size: CGSize(width: 48, height: 48))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.libraryItem.isVideo ? "Video" : "Photo")
                                        .font(.headline)
                                    Text("Saved \(FormatHelpers.bytes(item.bytesSaved))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if case .done(_, let note) = item.state, let note {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                if !failedItems.isEmpty {
                    section(title: "Couldn't compress") {
                        ForEach(failedItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.libraryItem.isVideo ? "Video" : "Photo")
                                        .font(.headline)
                                    if case .failed(let reason) = item.state {
                                        Text(reason)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Retry") {
                                    appState.batch.retry(item: item)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Retry item")
                            }
                        }
                    }
                }

                if let deleteError = appState.batch.lastDeleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }

                if !reviewItems.isEmpty {
                    section(title: "Review originals") {
                        ForEach(reviewItems) { item in
                            HStack(spacing: 12) {
                                AssetThumbnailView(asset: item.libraryItem.asset, size: CGSize(width: 48, height: 48))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.libraryItem.isVideo ? "Video" : "Photo")
                                        .font(.headline)
                                    if item.originalDeleted {
                                        Text("Moved ✓")
                                            .font(.subheadline)
                                            .foregroundStyle(.green)
                                    } else {
                                        Button("Move original to Recently Deleted") {
                                            pendingDelete = item
                                            showDeleteAlert = true
                                        }
                                        .font(.subheadline)
                                        .accessibilityLabel("Move original to Recently Deleted")
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        if appState.lastBatchWasFirstWin && !appState.store.isUnlocked {
                            appState.route = .paywall
                        } else {
                            appState.route = .main
                        }
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }
                    .accessibilityLabel("Continue")

                    Button("Compress more") {
                        appState.route = .finder
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Compress more")
                }
            }
            .padding()
        }
        .alert("Move original to Recently Deleted?", isPresented: $showDeleteAlert) {
            Button("Move to Recently Deleted", role: .destructive) {
                if let item = pendingDelete {
                    Task { await appState.batch.deleteOriginal(item) }
                }
                pendingDelete = nil
            }
            Button("Keep Original", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("The original moves to Recently Deleted for 30 days. Your compressed copy stays.")
        }
        .onReceive(appState.batch.objectWillChange) { _ in refreshSeed = UUID() }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 12) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
