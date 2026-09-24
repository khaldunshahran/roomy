import SwiftUI

/// Main tab bar: Clean Up + Settings.
struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            SpaceFinderView()
                .tabItem {
                    Label("Clean Up", systemImage: "sparkles")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
