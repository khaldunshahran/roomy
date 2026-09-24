import SwiftUI

/// Root of the Roomy app. Swaps the visible screen based on `AppState.route`.
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.route {
            case .welcome:
                WelcomeView()
            case .access:
                AccessView()
            case .finder:
                SpaceFinderView()
            case .selection:
                SelectionView()
            case .preview:
                PreviewView()
            case .progress:
                BatchProgressView()
            case .result:
                ResultView()
            case .paywall:
                PaywallView()
            case .reminderOptIn:
                ReminderOptInView()
            case .main:
                MainTabView()
            }
        }
        .environmentObject(appState)
    }
}
