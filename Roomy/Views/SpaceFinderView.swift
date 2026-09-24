import SwiftUI

/// Scans the library for the largest assets and shows the reclaim estimate.
struct SpaceFinderView: View {
    @EnvironmentObject var appState: AppState

    @State private var isLoading = true
    @State private var refreshSeed = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            content

            Button {
                appState.route = .selection
            } label: {
                Text("Choose What to Shrink")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(appState.finderItems.isEmpty ? Color.gray : Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .disabled(appState.finderItems.isEmpty)
            .accessibilityLabel("Choose What to Shrink")
            .padding()
            .background(.bar)
        }
        .task { await load() }
        .onReceive(appState.library.objectWillChange) { _ in refreshSeed = UUID() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You could free about \(FormatHelpers.bytes(appState.finderEstimateBytes))")
                .font(.title2)
                .fontWeight(.bold)
            Text("Estimate. Actual savings are measured after compression.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if appState.library.accessState == .denied {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Roomy can't see your photos.")
                    .font(.headline)
                Text("Allow photo access in Settings to find space to free.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            VStack {
                SwiftUI.ProgressView("Scanning your library…")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.finderItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Nothing big to shrink right now.")
                    .font(.headline)
                Text("Your largest photos and videos will show up here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(appState.finderItems) { item in
                row(for: item)
            }
            .listStyle(.plain)
        }
    }

    private func row(for item: LibraryItem) -> some View {
        HStack(spacing: 12) {
            AssetThumbnailView(asset: item.asset, size: CGSize(width: 64, height: 64))

            VStack(alignment: .leading, spacing: 4) {
                Text(kindLabel(for: item))
                    .font(.headline)
                Text(FormatHelpers.bytes(item.originalBytes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if item.isVideo {
                    Text(FormatHelpers.duration(item.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if item.isHDR {
                    badge("HDR")
                }
                if BatchEngine.completedIDs().contains(item.id) {
                    badge("Done")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func kindLabel(for item: LibraryItem) -> String {
        if item.isVideo { return "Video" }
        if item.isLivePhoto { return "Live Photo" }
        return "Photo"
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard appState.library.accessState != .denied else {
            appState.finderItems = []
            appState.finderEstimateBytes = 0
            return
        }
        let items = await appState.library.fetchLargestAssets(limit: 40)
        appState.finderItems = items
        let topBytes = items.prefix(40).reduce(Int64(0)) { $0 + $1.originalBytes }
        appState.finderEstimateBytes = Int64(Double(topBytes) * Config.Estimate.smartRatio)
    }
}
