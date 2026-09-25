import SwiftUI

@main
struct RoomyApp: App {
    @StateObject private var appState = AppState()

    init() {
        ReminderScheduler.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            // RootView is provided by the views module.
            RootView()
                .environmentObject(appState)
                .task {
                    // If photo access was already granted, start the library
                    // scan immediately in the background so results are ready
                    // by the time the user reaches the finder.
                    appState.initialLibraryCheck()
                }
        }
    }
}
