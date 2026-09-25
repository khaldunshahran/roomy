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

    private var overallProgress: Double {
        let items = appState.batch.items
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + progressValue(of: $1.state) }
        return total / Double(items.count)
    }

    private func progressValue(of state: BatchItemState) -> Double {
        switch state {
        case .pending: return 0
        case .downloadingFromICloud(let p): return p * 0.2
        case .encoding(let p): return 0.2 + p * 0.6
        case .verifying: return 0.85
        case .saving: return 0.95
        case .done: return 1
        case .failed: return 1
        case .cancelled: return 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(appState.batch.isRunning ? "Compressing…" : "Finished")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                SwiftUI.ProgressView(value: overallProgress)
                    .tint(Color.accentColor)
                    .accessibilityLabel("Overall progress")
                Text("\(appState.batch.doneCount) done · \(appState.batch.failedCount) failed · \(appState.batch.items.count) total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(appState.batch.items) { item in
                        BatchItemRow(item: item)
                    }
                }
                .padding()
            }

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
                            .cornerRadius(RoomyStyle.corner)
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
                            .roomyPrimaryButton()
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
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.libraryItem.isVideo ? "Video" : "Photo")
                        .font(.headline)
                    Spacer()
                    statusPill
                }
                stateView
            }
        }
        .roomyCard(padding: 12)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch item.state {
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
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
                    .tint(Color.accentColor)
                    .accessibilityLabel("Downloading from iCloud")
                Text("Downloading from iCloud… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .encoding(let progress):
            VStack(alignment: .leading, spacing: 4) {
                SwiftUI.ProgressView(value: progress)
                    .tint(Color.accentColor)
                    .accessibilityLabel("Compressing")
                Text("Compressing… \(Int(progress * 100))%")
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
                    .accessibilityLabel("Saving…")
                Text("Saving…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done(let bytesSaved, let note):
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved \(FormatHelpers.bytes(bytesSaved))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Text(reason)
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
