import SwiftUI

/// Per-item progress for the running compression batch.
///
/// Named `BatchProgressView` (instead of `ProgressView`) so it doesn't shadow
/// `SwiftUI.ProgressView`, which is used inside the rows.
struct BatchProgressView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshSeed = UUID()

    private var allTerminal: Bool {
        !appState.batch.items.isEmpty && appState.batch.items.allSatisfy { item in
            switch item.state {
            case .done, .failed, .cancelled:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(appState.batch.isRunning ? "Compressing…" : "Finished")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(appState.batch.doneCount) done · \(appState.batch.failedCount) failed · \(appState.batch.items.count) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            List(appState.batch.items) { item in
                BatchItemRow(item: item)
            }
            .listStyle(.plain)

            VStack(spacing: 12) {
                if appState.batch.isRunning {
                    Button(role: .destructive) {
                        appState.batch.cancel()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.12))
                            .foregroundStyle(.red)
                            .cornerRadius(14)
                    }
                    .accessibilityLabel("Cancel compression")
                    .accessibilityHint("Keeps everything already compressed.")
                } else if allTerminal {
                    Button {
                        appState.lastResultBytesSaved = appState.batch.measuredBytesSaved
                        appState.lastResultItemCount = appState.batch.doneCount
                        appState.remainingEstimateBytes = max(0, appState.finderEstimateBytes - appState.batch.measuredBytesSaved)
                        appState.route = .result
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }
                    .accessibilityLabel("Continue to results")
                }
            }
            .padding()
            .background(.bar)
        }
        .onReceive(appState.batch.objectWillChange) { _ in refreshSeed = UUID() }
    }
}

private struct BatchItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: BatchItem

    var body: some View {
        HStack(spacing: 12) {
            AssetThumbnailView(asset: item.libraryItem.asset, size: CGSize(width: 56, height: 56))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.libraryItem.isVideo ? "Video" : "Photo")
                    .font(.headline)
                stateView
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateView: some View {
        switch item.state {
        case .pending:
            Text("Waiting…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .downloadingFromICloud(let progress):
            VStack(alignment: .leading, spacing: 4) {
                SwiftUI.ProgressView(value: progress)
                    .accessibilityLabel("Downloading from iCloud")
                Text("Downloading from iCloud…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .encoding(let progress):
            VStack(alignment: .leading, spacing: 4) {
                SwiftUI.ProgressView(value: progress)
                    .accessibilityLabel("Compressing")
                Text("Compressing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            HStack(spacing: 8) {
                SwiftUI.ProgressView()
                    .accessibilityLabel("Verifying")
                Text("Verifying…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .saving:
            HStack(spacing: 8) {
                SwiftUI.ProgressView()
                    .accessibilityLabel("Saving")
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done(let bytesSaved, let note):
            VStack(alignment: .leading, spacing: 2) {
                Label("Saved \(FormatHelpers.bytes(bytesSaved))", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 4) {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Retry") {
                    appState.batch.retry(item: item)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Retry item")
            }
        case .cancelled:
            Text("Cancelled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
