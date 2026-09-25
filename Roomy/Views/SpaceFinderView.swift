import SwiftUI

/// Scans the library for the largest assets and shows the reclaim estimate.
struct SpaceFinderView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshSeed = UUID()

    private var isScanning: Bool { appState.libraryScanState == .scanning }

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
        // The scan runs once in the background (see AppState); this screen
        // only ensures it has been kicked off, never re-runs it on appear.
        .onAppear { appState.startLibraryScanIfNeeded() }
        .onReceive(appState.library.objectWillChange) { _ in refreshSeed = UUID() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("You could free about \(FormatHelpers.bytes(appState.finderEstimateBytes))")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    appState.rescanLibrary()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .disabled(isScanning)
                .accessibilityLabel("Rescan library")
            }
            if isScanning && !appState.finderItems.isEmpty {
                Text("Updating… \(Int(appState.libraryScanProgress * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Estimate. Actual savings are measured after compression.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        } else if isScanning && appState.finderItems.isEmpty {
            VStack(spacing: 12) {
                SwiftUI.ProgressView(value: appState.libraryScanProgress)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Scanning your library")
                Text("Scanning your library… \(Int(appState.libraryScanProgress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
}
