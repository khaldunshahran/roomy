import SwiftUI
import StoreKit

/// One-time-purchase paywall shown after the free cleanup.
struct PaywallView: View {
    @EnvironmentObject var appState: AppState

    @State private var refreshSeed = UUID()

    private var saved: String { FormatHelpers.bytes(appState.lastResultBytesSaved) }
    private var remaining: String { FormatHelpers.bytes(appState.remainingEstimateBytes) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("There's still \(remaining) waiting for you.")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("You just freed \(saved), free. Imagine what the rest feels like.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let product = appState.store.product {
                    VStack(spacing: 4) {
                        Text("ROOMY FOREVER — \(product.displayPrice)")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("One payment. Not per month.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    bullet("Shrink unlimited photos and videos")
                    bullet("See before and after before anything happens")
                    bullet("Originals kept safe in Recently Deleted for 30 days")
                    bullet("No ads. No subscriptions. Ever.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let product = appState.store.product {
                    Text("Quick math: iCloud+ is €2.99 a month, forever. A bigger iPhone is €900+. Roomy is \(product.displayPrice), once.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await appState.store.purchase() }
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isBuyEnabled ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                }
                .disabled(!isBuyEnabled)
                .accessibilityLabel("Get Roomy Forever")

                if appState.store.product == nil {
                    Button("Try Again") {
                        Task { await appState.store.load() }
                    }
                    .accessibilityLabel("Try Again")
                }

                if let error = appState.store.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Restore purchases") {
                    Task { await appState.store.restore() }
                }
                .accessibilityLabel("Restore purchases")

                HStack(spacing: 6) {
                    Text("One-time purchase")
                    Text("·")
                        .accessibilityHidden(true)
                    Button("Restore purchases") {
                        Task { await appState.store.restore() }
                    }
                    .accessibilityLabel("Restore purchases")
                    Text("·")
                        .accessibilityHidden(true)
                    if let terms = URL(string: Config.appleStandardEULAURLString) {
                        Link("Terms", destination: terms)
                    }
                    Text("·")
                        .accessibilityHidden(true)
                    if let privacy = URL(string: Config.privacyPolicyURLString) {
                        Link("Privacy", destination: privacy)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Button("Maybe later →") {
                    appState.route = .reminderOptIn
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Maybe later")
            }
            .padding()
        }
        .task { await appState.store.load() }
        .onChange(of: appState.store.isUnlocked) { _, unlocked in
            if unlocked {
                appState.route = .main
            }
        }
        .onReceive(appState.store.objectWillChange) { _ in refreshSeed = UUID() }
    }

    private var isBuyEnabled: Bool {
        appState.store.product != nil && !appState.store.purchaseInProgress
    }

    private var buttonTitle: String {
        if appState.store.purchaseInProgress { return "Working…" }
        if appState.store.product == nil { return "Loading price…" }
        return "Get Roomy Forever"
    }

    private func bullet(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
    }
}
