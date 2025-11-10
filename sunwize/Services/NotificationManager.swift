import Foundation
import UserNotifications

// MARK: - Notification Manager
@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        setupNotifications()
    }

    // MARK: - Setup

    private func setupNotifications() {
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = granted
            }
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    private func checkAuthorizationStatus() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            await MainActor.run {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - UV Notifications

    func sendUVWarningNotification(exposureRatio: Double) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "UV Exposure Warning"
        content.body = String(format: "You've reached %.0f%% of your safe UV limit. Consider applying sunscreen or seeking shade.", exposureRatio * 100)
        content.sound = .default
        content.categoryIdentifier = "UV_WARNING"

        // Add action buttons
        content.userInfo = ["type": "uv_warning", "exposure_ratio": exposureRatio]

        let request = UNNotificationRequest(
            identifier: "uv_warning_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Send immediately
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to send UV warning notification: \(error)")
        }
    }

    func sendUVDangerNotification(exposureRatio: Double) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "⚠️ UV Exposure Danger"
        content.body = "You've exceeded your safe UV limit! Please seek shade immediately to prevent sunburn."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.caf")) // Custom sound if available
        content.categoryIdentifier = "UV_DANGER"
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .critical
        }

        content.userInfo = ["type": "uv_danger", "exposure_ratio": exposureRatio]

        let request = UNNotificationRequest(
            identifier: "uv_danger_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to send UV danger notification: \(error)")
        }
    }

    // MARK: - Vitamin D Notifications

    func sendVitaminDTargetReachedNotification() async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "🎉 Vitamin D Target Reached!"
        content.body = "Great job! You've reached your daily Vitamin D target from safe sun exposure."
        content.sound = .default
        content.categoryIdentifier = "VITAMIN_D_SUCCESS"

        content.userInfo = ["type": "vitamin_d_target"]

        let request = UNNotificationRequest(
            identifier: "vitamin_d_\(dateKey())",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to send Vitamin D notification: \(error)")
        }
    }

    // MARK: - Body Scan Reminders

    func scheduleMonthlyBodyScanReminder() async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Monthly Body Scan Reminder"
        content.body = "It's time for your monthly body scan. Track any changes in your skin spots for early detection."
        content.sound = .default
        content.categoryIdentifier = "BODY_SCAN_REMINDER"

        content.userInfo = ["type": "body_scan_reminder"]

        // Schedule for the first day of next month at 10 AM
        var dateComponents = DateComponents()
        dateComponents.day = 1
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "monthly_body_scan",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule body scan reminder: \(error)")
        }
    }

    func cancelBodyScanReminders() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["monthly_body_scan"])
    }

    // MARK: - Sunscreen Reminders

    func scheduleSunscreenReapplicationReminder(after duration: TimeInterval) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to Reapply Sunscreen"
        content.body = "Your sunscreen protection is wearing off. Reapply to maintain protection."
        content.sound = .default
        content.categoryIdentifier = "SUNSCREEN_REMINDER"

        content.userInfo = ["type": "sunscreen_reminder"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)

        let request = UNNotificationRequest(
            identifier: "sunscreen_reminder",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule sunscreen reminder: \(error)")
        }
    }

    func cancelSunscreenReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["sunscreen_reminder"])
    }

    // MARK: - Daily Summary

    func sendDailySummaryNotification(totalSED: Double, vitaminDIU: Double) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Daily Sun Exposure Summary"
        content.body = String(format: "Today: %.1f SED exposure, %.0f IU Vitamin D synthesized", totalSED, vitaminDIU)
        content.sound = .default
        content.categoryIdentifier = "DAILY_SUMMARY"

        content.userInfo = ["type": "daily_summary", "sed": totalSED, "vitamin_d": vitaminDIU]

        let request = UNNotificationRequest(
            identifier: "daily_summary_\(dateKey())",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to send daily summary: \(error)")
        }
    }

    // MARK: - Notification Categories

    func setupNotificationCategories() {
        // UV Warning actions
        let applySunscreenAction = UNNotificationAction(
            identifier: "APPLY_SUNSCREEN",
            title: "Apply Sunscreen",
            options: [.foreground]
        )

        let goInsideAction = UNNotificationAction(
            identifier: "GO_INSIDE",
            title: "I'm Going Inside",
            options: []
        )

        let uvWarningCategory = UNNotificationCategory(
            identifier: "UV_WARNING",
            actions: [applySunscreenAction, goInsideAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let uvDangerCategory = UNNotificationCategory(
            identifier: "UV_DANGER",
            actions: [goInsideAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Body Scan Reminder actions
        let startScanAction = UNNotificationAction(
            identifier: "START_SCAN",
            title: "Start Body Scan",
            options: [.foreground]
        )

        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind Me Tomorrow",
            options: []
        )

        let bodyScanCategory = UNNotificationCategory(
            identifier: "BODY_SCAN_REMINDER",
            actions: [startScanAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )

        // Set categories
        notificationCenter.setNotificationCategories([
            uvWarningCategory,
            uvDangerCategory,
            bodyScanCategory
        ])
    }

    // MARK: - Helpers

    private func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification actions
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        Task { @MainActor in
            switch actionIdentifier {
            case "APPLY_SUNSCREEN":
                // Handle sunscreen application
                await BackgroundTaskManager.shared.applySunscreen()

            case "GO_INSIDE":
                // End UV session
                // This would update the location mode
                break

            case "START_SCAN":
                // Navigate to body scan tab
                NotificationCenter.default.post(name: .navigateToBodyScan, object: nil)

            case "REMIND_LATER":
                // Schedule reminder for tomorrow
                await scheduleBodyScanReminderTomorrow()

            default:
                break
            }
        }

        completionHandler()
    }

    private func scheduleBodyScanReminderTomorrow() async {
        let content = UNMutableNotificationContent()
        content.title = "Body Scan Reminder"
        content.body = "Don't forget to complete your body scan today."
        content.sound = .default
        content.categoryIdentifier = "BODY_SCAN_REMINDER"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 86400, repeats: false) // 24 hours

        let request = UNNotificationRequest(
            identifier: "body_scan_tomorrow",
            content: content,
            trigger: trigger
        )

        try? await notificationCenter.add(request)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let navigateToBodyScan = Notification.Name("navigateToBodyScan")
    static let navigateToUVTracking = Notification.Name("navigateToUVTracking")
}
