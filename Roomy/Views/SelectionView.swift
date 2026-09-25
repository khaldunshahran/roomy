import SwiftUI

/// Pick which assets to shrink, and at which quality preset.
struct SelectionView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedIDs: Set<String> = []
    @State private var showCapAlert = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    /// Fixed cell size (3 columns). Avoids a GeometryReader per cell, which
    /// forces extra layout passes and made the grid feel sluggish.
    private var cellSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let sidePadding: CGFloat = 16 * 2 // the ScrollView content's .padding()
        let spacing: CGFloat = 10 * 2     // between the 3 columns
        return (screenWidth - sidePadding - spacing) / 3
    }

    private var selectedItems: [LibraryItem] {
        appState.finderItems.filter { selectedIDs.contains($0.id) }
    }

    private var estimatedSavings: Int64 {
        let bytes = selectedItems.reduce(Int64(0)) { $0 + $1.originalBytes }
        return Int64(Double(bytes) * ratio(for: appState.preset))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if appState.isFirstWinAvailable {
                        firstWinBanner
                    }

                    presetPicker

                    HStack {
                        Text("\(selectedIDs.count) selected")
                            .font(.headline)
                        Spacer()
                        Button("Select all") { selectAll() }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .accessibilityLabel("Select all")
                        Button("Clear") { selectedIDs.removeAll() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Clear selection")
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(appState.finderItems) { item in
                            cell(for: item, width: cellSize)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
                .padding()
            }

            VStack(spacing: 8) {
                if !selectedIDs.isEmpty {
                    Text("\(appState.preset.title) saves about \(FormatHelpers.bytes(estimatedSavings))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                Button {
                    appState.selectedItems = selectedItems
                    appState.route = .preview
                } label: {
                    Text(selectedIDs.isEmpty ? "Select items to continue" : "Preview (\(selectedIDs.count))")
                        .roomyPrimaryButton(isEnabled: !selectedIDs.isEmpty)
                }
                .disabled(selectedIDs.isEmpty)
                .accessibilityLabel("Preview")
            }
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
        HStack(spacing: 10) {
            Image(systemName: "gift.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Your free cleanup is \(Config.FirstWin.maxItems) items. You pick which.")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .roomyCard(padding: 12)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(QualityPreset.allCases) { preset in
                    let isActive = appState.preset == preset
                    Button {
                        appState.preset = preset
                    } label: {
                        VStack(spacing: 2) {
                            Text(preset.title)
                                .font(.subheadline)
                                .fontWeight(isActive ? .bold : .medium)
                            Text(preset.shortTagline)
                                .font(.caption2)
                                .foregroundStyle(isActive ? Color.white.opacity(0.85) : Color.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isActive ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(isActive ? .white : .primary)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.title) quality")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            Text(appState.preset.tagline)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                    .cornerRadius(12)

                MediaBadge(item: item)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .frame(width: 28, height: 28)
                    Image(systemName: isSelected ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .padding(6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
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
