import SwiftUI

/// First screen. Brand promise + entry into the photo-access flow.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Roomy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Free the storage. Keep the memories.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                PromiseRow(icon: "iphone", text: "On-device — your media never leaves your phone")
                PromiseRow(icon: "nosign", text: "No ads")
                PromiseRow(icon: "key.fill", text: "Pay once — one purchase unlocks everything")
            }
            .padding(.horizontal)

            Spacer()

            Button {
                appState.route = .access
            } label: {
                Text("Choose Photos & Videos")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .accessibilityLabel("Choose Photos & Videos")
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

private struct PromiseRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
    }
}
