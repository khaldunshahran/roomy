import SwiftUI

/// Pick which assets to shrink, and at which quality preset.
struct SelectionView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedIDs: Set<String> = []
    @State private var showCapAlert = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    private var selectedItems: [LibraryItem] {
        appState.finderItems.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if appState.isFirstWinAvailable {
                        firstWinBanner
                    }

                    presetCards

                    estimateLine

                    HStack {
                        Text("\(selectedIDs.count) selected")
                            .font(.headline)
                        Spacer()
                        Button("Select all") { selectAll() }
                            .accessibilityLabel("Select all")
                        Button("Clear") { selectedIDs.removeAll() }
                            .accessibilityLabel("Clear selection")
                    }

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(appState.finderItems) { item in
                            GeometryReader { geo in
                                cell(for: item, width: geo.size.width)
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .padding()
            }

            Button {
                appState.selectedItems = selectedItems
                appState.route = .preview
            } label: {
                Text("Preview")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedIDs.isEmpty ? Color.gray : Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .disabled(selectedIDs.isEmpty)
            .accessibilityLabel("Preview")
            .padding()
            .background(.bar)
        }
        .alert("Free cleanup limit", isPresented: $showCapAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free cleanup covers \(Config.FirstWin.maxItems) items — deselect one or continue with \(Config.FirstWin.maxItems).")
        }
    }

    private var firstWinBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "gift.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Your free cleanup is \(Config.FirstWin.maxItems) items. You pick which.")
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
    }

    private var presetCards: some View {
        VStack(spacing: 8) {
            ForEach(QualityPreset.allCases) { preset in
                let isActive = appState.preset == preset
                Button {
                    appState.preset = preset
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.title)
                                .font(.headline)
                            Text(preset.tagline)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.title) quality")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }

    private var estimateLine: some View {
        let bytes = selectedItems.reduce(Int64(0)) { $0 + $1.originalBytes }
        let saved = Int64(Double(bytes) * ratio(for: appState.preset))
        return Text("\(appState.preset.title) saves about \(FormatHelpers.bytes(saved))")
            .font(.headline)
    }

    private func ratio(for preset: QualityPreset) -> Double {
        switch preset {
        case .smart: return Config.Estimate.smartRatio
        case .smaller: return Config.Estimate.smallerRatio
        case .best: return Config.Estimate.bestRatio
        }
    }

    private func cell(for item: LibraryItem, width: CGFloat) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Button {
            toggle(item)
        } label: {
            ZStack(alignment: .topTrailing) {
                AssetThumbnailView(asset: item.asset, size: CGSize(width: width, height: width))

                if item.isVideo {
                    Text(FormatHelpers.duration(item.duration))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kindLabel(for: item)) \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func kindLabel(for item: LibraryItem) -> String {
        if item.isVideo { return "Video" }
        if item.isLivePhoto { return "Live Photo" }
        return "Photo"
    }

    private func toggle(_ item: LibraryItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            if appState.isFirstWinAvailable && selectedIDs.count >= Config.FirstWin.maxItems {
                showCapAlert = true
                return
            }
            selectedIDs.insert(item.id)
        }
    }

    private func selectAll() {
        var ids = Set(appState.finderItems.map(\.id))
        if appState.isFirstWinAvailable && ids.count > Config.FirstWin.maxItems {
            ids = Set(ids.prefix(Config.FirstWin.maxItems))
            showCapAlert = true
        }
        selectedIDs = ids
    }
}
