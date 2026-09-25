import SwiftUI
import Photos

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
            VStack(spacing: 20) {
                heroCard

                if !doneItems.isEmpty {
                    section(title: "Compressed") {
                        ForEach(doneItems) { item in
                            HStack(spacing: 12) {
                                AssetThumbnailView(asset: item.libraryItem.asset, size: CGSize(width: 52, height: 52))
                                    .cornerRadius(10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.libraryItem.isVideo ? "Video" : "Photo")
                                        .font(.headline)
                                    Text("Saved \(FormatHelpers.bytes(item.bytesSaved))")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.green)
                                    if case .done(_, let note) = item.state, let note {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                            }
                            .roomyCard(padding: 12)
                        }
                    }
                }

                if !failedItems.isEmpty {
                    section(title: "Couldn't compress") {
                        ForEach(failedItems) { item in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.red.opacity(0.12))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                        .accessibilityHidden(true)
                                }
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
                            .roomyCard(padding: 12)
                        }
                    }
                }

                if let deleteError = appState.batch.lastDeleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .roomyCard(padding: 12)
                }

                if !reviewItems.isEmpty {
                    section(title: "Review originals") {
                        Text("Preview each compressed copy, then decide what happens to the original. Originals only ever move to Recently Deleted — nothing is permanently erased.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(reviewItems) { item in
                            ReviewRow(item: item) { tapped in
                                pendingDelete = tapped
                                showDeleteAlert = true
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        if appState.lastBatchWasFirstWin && !appState.store.isUnlocked {
                            appState.route = .paywall
                        } else {
                            appState.route = .main
                        }
                    } label: {
                        Text("Done")
                            .roomyPrimaryButton()
                    }
                    .accessibilityLabel("Continue")

                    Button("Compress more") {
                        appState.route = .finder
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Compress more")
                }
                .padding(.top, 4)
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

    private var heroCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "party.popper.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("You freed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(FormatHelpers.bytes(appState.lastResultBytesSaved))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
            Text("\(appState.lastResultItemCount) items compressed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(RoomyStyle.corner)
        .padding(.top, 8)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
            VStack(spacing: 10) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One review row: preview the compressed copy, see the saving, then decide
/// what happens to the original. Deletion always goes to iOS Recently
/// Deleted (recoverable) and is only offered after a verified save.
private struct ReviewRow: View {
    let item: BatchItem
    let onDeleteTap: (BatchItem) -> Void

    @State private var compressedAsset: PHAsset?
    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AssetThumbnailView(asset: compressedAsset ?? item.libraryItem.asset, size: CGSize(width: 52, height: 52))
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.libraryItem.isVideo ? "Video" : "Photo")
                        .font(.headline)
                    Text("Saved \(FormatHelpers.bytes(item.bytesSaved))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                Spacer()
                if item.originalDeleted {
                    Label("Moved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
            if !item.originalDeleted {
                HStack(spacing: 10) {
                    Button {
                        showPreview = true
                    } label: {
                        Label("Preview copy", systemImage: "eye.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(10)
                    }
                    .accessibilityLabel("Preview compressed copy")
                    Button {
                        onDeleteTap(item)
                    } label: {
                        Label("Delete original", systemImage: "trash")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .cornerRadius(10)
                    }
                    .accessibilityLabel("Move original to Recently Deleted")
                }
            }
        }
        .roomyCard()
        .task {
            if compressedAsset == nil, let id = item.verifiedCopyLocalIdentifier {
                compressedAsset = PhotoLibraryService.fetchAsset(localIdentifier: id)
            }
        }
        .sheet(isPresented: $showPreview) {
            CompressedPreviewSheet(item: item)
        }
    }
}
