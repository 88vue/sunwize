import Foundation
import UserNotifications
import UIKit

// MARK: - Notification Manager
@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var deviceToken: String?
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

            // Register for remote notifications if permission granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }

            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - Push Notifications

    func registerDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
        print("📱 Device token registered: \(token)")

        // Save to Supabase
        Task {
            await saveDeviceTokenToDatabase(token)
        }
    }

    func handleRegistrationError(_ error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }

    private func saveDeviceTokenToDatabase(_ token: String) async {
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else {
            print("❌ Cannot save device token: No authenticated user")
            return
        }

        do {
            struct PushToken: Encodable {
                let user_id: String
                let device_token: String
                let updated_at: String
            }

            let tokenData = PushToken(
                user_id: userId.uuidString,
                device_token: token,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )

            // Upsert token (insert or update if exists)
            try await SupabaseManager.shared.client
                .from("push_tokens")
                .upsert(tokenData, onConflict: "user_id,device_token")
                .execute()

            print("✅ Device token saved to database")
        } catch {
            print("❌ Failed to save device token: \(error)")
        }
    }

    func removeDeviceToken() async {
        guard let token = deviceToken,
              let userId = try? await SupabaseManager.shared.client.auth.session.user.id else {
            return
        }

        do {
            try await SupabaseManager.shared.client
                .from("push_tokens")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("device_token", value: token)
                .execute()

            print("✅ Device token removed from database")
            self.deviceToken = nil
        } catch {
            print("❌ Failed to remove device token: \(error)")
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
        content.body = String(format: "You've reached %.0f%% of your safe UV limit. Consider seeking shade.", exposureRatio * 100)
        content.sound = .default
        content.categoryIdentifier = "UV_WARNING"
        content.userInfo = ["type": "uv_warning", "exposure_ratio": exposureRatio]

        let request = UNNotificationRequest(
            identifier: "uv_warning_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Send immediately
        )

        do {
            try await notificationCenter.add(request)
            print("⚠️ UV warning notification sent (\(Int(exposureRatio * 100))%)")
        } catch {
            print("❌ Failed to send UV warning notification: \(error)")
        }
    }

    func sendUVDangerNotification(exposureRatio: Double) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "⚠️ UV Exposure Danger"
        content.body = "You've exceeded your safe UV limit! Please seek shade immediately to prevent sunburn."
        content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.caf"))
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
            print("🚨 UV danger notification sent")
        } catch {
            print("❌ Failed to send UV danger notification: \(error)")
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
            print("🎉 Vitamin D target reached notification sent")
        } catch {
            print("❌ Failed to send Vitamin D notification: \(error)")
        }
    }

    // MARK: - Morning UV Peak Notification

    func scheduleMorningUVPeakNotification(peakUVTime: String, peakUVIndex: Double) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "☀️ Today's UV Peak"
        content.body = String(format: "Peak UV index of %.1f expected around %@. Plan your outdoor activities accordingly.", peakUVIndex, peakUVTime)
        content.sound = .default
        content.categoryIdentifier = "MORNING_UV_PEAK"
        content.userInfo = ["type": "morning_uv_peak", "peak_time": peakUVTime, "peak_uv": peakUVIndex]

        // Schedule for 8 AM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 8
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "morning_uv_peak",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            print("☀️ Morning UV peak notification scheduled for 8 AM daily")
        } catch {
            print("❌ Failed to schedule morning UV peak notification: \(error)")
        }
    }

    func cancelMorningUVPeakNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["morning_uv_peak"])
    }

    // MARK: - Body Spot Tracker Reminders

    func scheduleMonthlyBodySpotReminder() async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Monthly Body Spot Tracker Reminder"
        content.body = "It's time for your monthly body spot check. Track any changes in your skin spots for early detection."
        content.sound = .default
        content.categoryIdentifier = "BODY_SPOT_REMINDER"
        content.userInfo = ["type": "body_spot_reminder"]

        // Schedule for the first day of every month at 10 AM
        var dateComponents = DateComponents()
        dateComponents.day = 1
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "monthly_body_spot",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            print("📅 Monthly body spot tracker reminder scheduled for 1st of each month at 10 AM")
        } catch {
            print("❌ Failed to schedule body spot tracker reminder: \(error)")
        }
    }

    func cancelBodySpotReminders() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["monthly_body_spot"])
    }

    // MARK: - Notification Categories

    func setupNotificationCategories() {
        // UV Warning category (no actions needed)
        let uvWarningCategory = UNNotificationCategory(
            identifier: "UV_WARNING",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // UV Danger category (no actions needed)
        let uvDangerCategory = UNNotificationCategory(
            identifier: "UV_DANGER",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Vitamin D Success category (no actions needed)
        let vitaminDCategory = UNNotificationCategory(
            identifier: "VITAMIN_D_SUCCESS",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Morning UV Peak category (no actions needed)
        let morningUVCategory = UNNotificationCategory(
            identifier: "MORNING_UV_PEAK",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Body Spot Tracker Reminder category (no actions needed)
        let bodySpotCategory = UNNotificationCategory(
            identifier: "BODY_SPOT_REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Set categories
        notificationCenter.setNotificationCategories([
            uvWarningCategory,
            uvDangerCategory,
            vitaminDCategory,
            morningUVCategory,
            bodySpotCategory
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
        // Handle notification tap (open app)
        // No custom actions needed for the 4 notification types
        completionHandler()
    }
}
