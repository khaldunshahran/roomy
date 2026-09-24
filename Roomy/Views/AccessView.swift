import SwiftUI
import UIKit

/// Explains photo access and handles the full / limited / denied outcomes.
struct AccessView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var showLimitedPanel = false
    @State private var showDeniedPanel = false
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                VStack(spacing: 8) {
                    Text("Roomy needs your photos")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("Start with just a few photos, or share your whole library. You stay in control.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if showLimitedPanel {
                    limitedPanel
                } else if showDeniedPanel {
                    deniedPanel
                } else {
                    Button {
                        Task { await request() }
                    } label: {
                        Text(isRequesting ? "Asking…" : "Choose Photos & Videos")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(14)
                    }
                    .accessibilityLabel("Choose Photos & Videos")
                    .disabled(isRequesting)
                    .padding(.horizontal)
                }

                Text("How limited access works: you pick exactly which photos and videos Roomy can see — nothing else. You can share more later, any time, from Settings or right here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func request() async {
        isRequesting = true
        defer { isRequesting = false }
        let state = await appState.library.requestAccess()
        switch state {
        case .full:
            appState.route = .finder
        case .limited:
            showLimitedPanel = true
        case .denied:
            showDeniedPanel = true
        case .notDetermined:
            break
        }
    }

    private var limitedPanel: some View {
        VStack(spacing: 12) {
            Text("You've shared part of your library.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Continue") {
                appState.route = .finder
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue")
            Button("Share More Photos") {
                appState.library.presentLimitedLibraryPicker()
            }
            .accessibilityLabel("Share More Photos")
        }
        .padding(.horizontal)
    }

    private var deniedPanel: some View {
        VStack(spacing: 12) {
            Text("Roomy can't see your photos.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Open Settings and allow photo access so Roomy can find space to free.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open Settings")
        }
        .padding(.horizontal)
    }
}
