import SwiftUI

/// Shows the estimated reclaimable space and the largest media items.
struct SpaceFinderView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshSeed = UUID()

    private var isScanning: Bool { appState.libraryScanState == .scanning }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard

                    if appState.library.accessState == .denied {
                        deniedCard
                    } else if isScanning && appState.finderItems.isEmpty {
                        scanningCard
                    } else if appState.finderItems.isEmpty {
                        emptyCard
                    } else {
                        VStack(spacing: 10) {
                            ForEach(appState.finderItems) { item in
                                itemCard(for: item)
                            }
                        }
                    }
                }
                .padding()
            }

            Button {
                appState.route = .selection
            } label: {
                Text("Choose What to Shrink")
                    .roomyPrimaryButton(isEnabled: !appState.finderItems.isEmpty)
            }
            .disabled(appState.finderItems.isEmpty)
            .accessibilityLabel("Choose What to Shrink")
            .padding()
            .background(.bar)
        }
        // The scan runs once in the background (see AppState); this screen
        // only ensures it has been kicked off, never re-runs it on appear.
        .onAppear { appState.startLibraryScanIfNeeded() }
        .onReceive(appState.library.objectWillChange) { _ in refreshSeed = UUID() }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You could free about")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(FormatHelpers.bytes(appState.finderEstimateBytes))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button {
                    appState.rescanLibrary()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .disabled(isScanning)
                .accessibilityLabel("Rescan library")
            }
            if isScanning {
                SwiftUI.ProgressView(value: appState.libraryScanProgress)
                    .accessibilityLabel("Scanning your library")
                Text("Scanning your library… \(Int(appState.libraryScanProgress * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Estimate. Actual savings are measured after compression.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .roomyCard()
    }

    private func itemCard(for item: LibraryItem) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                AssetThumbnailView(asset: item.asset, size: CGSize(width: 64, height: 64))
                    .cornerRadius(10)
                MediaBadge(item: item)
                    .padding(4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isVideo ? "Video" : (item.isLivePhoto ? "Live Photo" : "Photo"))
                    .font(.headline)
                Text("\(item.pixelWidth) × \(item.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(FormatHelpers.bytes(item.originalBytes))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .roomyCard(padding: 10)
    }

    private var deniedCard: some View {
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
        .roomyCard()
    }

    private var scanningCard: some View {
        VStack(spacing: 12) {
            SwiftUI.ProgressView(value: appState.libraryScanProgress)
                .frame(maxWidth: 220)
                .accessibilityLabel("Scanning your library")
            Text("Scanning your library… \(Int(appState.libraryScanProgress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .roomyCard()
        .frame(maxWidth: .infinity)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
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
        .roomyCard()
    }
}
