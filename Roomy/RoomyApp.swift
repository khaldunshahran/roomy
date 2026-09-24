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
        }
    }
}
