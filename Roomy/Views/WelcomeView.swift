import SwiftUI

/// First screen. Brand promise + entry into the photo-access flow.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            RoomyAppMark(size: 96)
                .padding(.bottom, 20)

            Text("Roomy")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Free the storage.\nKeep the memories.")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                PromiseRow(icon: "cpu", text: "100% on-device — your media never leaves your phone")
                PromiseRow(icon: "nosign", text: "No ads, no subscriptions, no nonsense")
                PromiseRow(icon: "key.fill", text: "Pay once — one purchase unlocks everything")
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                appState.route = .access
            } label: {
                Text("Choose Photos & Videos")
                    .roomyPrimaryButton()
            }
            .accessibilityLabel("Choose Photos & Videos")
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Text("iOS 17+ · Works with limited photo access")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 28)
        }
    }
}

private struct PromiseRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.subheadline)
            Spacer()
        }
        .roomyCard(padding: 12)
    }
}
