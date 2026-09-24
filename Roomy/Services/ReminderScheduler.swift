import Foundation
import UserNotifications
import BackgroundTasks

/// Local-only reminder scheduling for the weekly/monthly "space check".
///
/// Strictly UNUserNotificationCenter: no push server, no device tokens, no
/// network. Denied notification permission never blocks anything — scheduled
/// reminders are simply skipped. Copy never promises analysis at an exact
/// hour, and a stale estimate is never presented as fresh: notifications only
/// carry a number when the cached estimate is under 72 hours old.
enum ReminderScheduler {

    enum Frequency: String, CaseIterable, Codable {
        case weekly
        case monthly
    }

    struct Schedule: Codable {
        var isEnabled: Bool
        var frequency: Frequency
        var weekday: Int   // 1 = Sunday ... 7 = Saturday (weekly only)
        var hour: Int
        var minute: Int
    }

    static var defaultSchedule: Schedule {
        Schedule(isEnabled: false, frequency: .weekly, weekday: 1, hour: 20, minute: 0)
    }

    static let notificationID = "roomy.spacecheck"

    private static let scheduleKey = "roomy.reminder.schedule"
    private static let estimateKey = "roomy.reminder.lastEstimateBytes"
    private static let estimateDateKey = "roomy.reminder.lastEstimateDate"
    private static let estimateFreshnessLimit: TimeInterval = 72 * 3600 // 72h

    // MARK: - Schedule persistence

    static func load() -> Schedule {
        guard let data = UserDefaults.standard.data(forKey: scheduleKey),
              let s = try? JSONDecoder().decode(Schedule.self, from: data) else {
            return defaultSchedule
        }
        return s
    }

    static func save(_ s: Schedule) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: scheduleKey)
        }
    }

    // MARK: - Authorization

    /// Ask for notification permission. A denial is a normal outcome: callers
    /// treat `false` as "reminders off", never as an error that blocks the app.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Cached estimate (bytes + timestamp)

    /// Store a fresh estimate with a timestamp. Updated when the user opens
    /// the app and after background refreshes. Never presented as fresh once
    /// older than 72 hours.
    static func updateCachedEstimate(bytes: Int64) {
        UserDefaults.standard.set(bytes, forKey: estimateKey)
        UserDefaults.standard.set(Date(), forKey: estimateDateKey)
    }

    /// Human-readable "About X · checked at Y" line for the UI, or nil when
    /// there is no cached estimate yet.
    static func lastEstimateText() -> String? {
        let b = UserDefaults.standard.object(forKey: estimateKey) as? Int64 ?? 0
        guard b > 0,
              let d = UserDefaults.standard.object(forKey: estimateDateKey) as? Date else {
            return nil
        }
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return "About \(FormatHelpers.bytes(b)) · checked \(df.string(from: d))"
    }

    /// The cached estimate only if it was taken within the last 72 hours;
    /// nil otherwise so stale numbers are never shown as current.
    private static func freshEstimate() -> Int64? {
        let b = UserDefaults.standard.object(forKey: estimateKey) as? Int64 ?? 0
        guard b > 0,
              let d = UserDefaults.standard.object(forKey: estimateDateKey) as? Date else {
            return nil
        }
        return Date().timeIntervalSince(d) < estimateFreshnessLimit ? b : nil
    }

    // MARK: - Scheduling

    /// Rebuild the single pending "space check" notification from the saved
    /// schedule. Safe to call anytime: removes the old request first, exits
    /// silently when reminders are off or notifications are denied.
    static func applySchedule() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let s = load()
        guard s.isEnabled else { return }

        // Notification denial never blocks anything: skip quietly.
        let status = await center.notificationSettings()
        guard status.authorizationStatus == .authorized
                || status.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Roomy"
        if let est = freshEstimate() {
            content.body = "About \(FormatHelpers.bytes(est)) may be ready to review."
        } else if s.frequency == .weekly {
            content.body = "Ready for your weekly space check?"
        } else {
            content.body = "Ready for your monthly space check?"
        }

        // Copy never promises analysis at an exact hour: the trigger fires at
        // the chosen time but the body carries no hour-specific claims.
        var comps = DateComponents()
        comps.hour = s.hour
        comps.minute = s.minute
        if s.frequency == .weekly {
            comps.weekday = s.weekday
        } else {
            comps.day = 1
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
        scheduleBackgroundRefresh()
    }

    /// Turn reminders off entirely: persist the disabled schedule and remove
    /// the pending request.
    static func disable() async {
        var s = load()
        s.isEnabled = false
        save(s)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    // MARK: - Background refresh (opportunistic; iOS decides if/when it runs)

    /// Register once at app launch. Call from the app delegate's
    /// `application(_:didFinishLaunchingWithOptions:)`.
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Config.Reminders.backgroundTaskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task {
                await handleBackgroundRefresh(refresh)
            }
        }
    }

    /// Queue the next opportunistic refresh aligned with the reminder
    /// frequency. Silently no-ops if reminders are disabled.
    static func scheduleBackgroundRefresh() {
        let s = load()
        guard s.isEnabled else { return }
        let interval: TimeInterval = (s.frequency == .weekly) ? 7 * 24 * 3600 : 30 * 24 * 3600
        let request = BGAppRefreshTaskRequest(identifier: Config.Reminders.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs in the background — all static, no @MainActor state.
    /// Re-schedules first so the cadence survives even if this run is cut off,
    /// then takes a lightweight, read-only size estimate (no image data is
    /// downloaded) and rebuilds the pending notification with the fresh number.
    private static func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh() // keep the cadence alive
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        if let est = await PhotoLibraryService.quickTopItemsEstimate(limit: 50) {
            updateCachedEstimate(bytes: est)
            await applySchedule() // refresh the pending notification with the fresh number
        }
        task.setTaskCompleted(success: true)
    }
}
