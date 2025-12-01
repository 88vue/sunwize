import Foundation
import UserNotifications

// MARK: - UV Notification Service

/// Service for UV-related notifications (exposure warnings, Vitamin D targets)
@MainActor
class UVNotificationService: ObservableObject {
    static let shared = UVNotificationService()

    // MARK: - Services

    private let notificationManager = NotificationManager.shared

    // MARK: - State

    private var lastNotificationTime = Date.distantPast
    private var lastWarningNotificationTime = Date.distantPast
    private var lastDangerNotificationTime = Date.distantPast
    private var vitaminDTargetNotificationSent = false

    // MARK: - Cooldowns

    private let notificationCooldown: TimeInterval = 300  // 5 minutes
    private let warningCooldown: TimeInterval = 600       // 10 minutes
    private let dangerCooldown: TimeInterval = 300        // 5 minutes for danger

    // MARK: - Initialization

    private init() {}

    // MARK: - UV Exposure Notifications

    /// Check and send UV exposure notifications
    func checkAndSendUVNotifications(
        exposureRatio: Double,
        profile: Profile
    ) async {
        let now = Date()

        // Check danger level (100% MED)
        if exposureRatio >= 1.0 {
            if now.timeIntervalSince(lastDangerNotificationTime) >= dangerCooldown {
                await sendDangerNotification(exposureRatio: exposureRatio)
                lastDangerNotificationTime = now
            }
            return
        }

        // Check warning level (80% MED)
        if exposureRatio >= 0.80 {
            if now.timeIntervalSince(lastWarningNotificationTime) >= warningCooldown {
                await sendWarningNotification(exposureRatio: exposureRatio)
                lastWarningNotificationTime = now
            }
        }
    }

    private func sendWarningNotification(exposureRatio: Double) async {
        await notificationManager.sendUVWarningNotification(exposureRatio: exposureRatio)
        print("[UVNotificationService] Warning notification sent: \(Int(exposureRatio * 100))% exposure")
    }

    private func sendDangerNotification(exposureRatio: Double) async {
        await notificationManager.sendUVDangerNotification(exposureRatio: exposureRatio)
        print("[UVNotificationService] Danger notification sent")
    }

    // MARK: - Vitamin D Notifications

    /// Check and send Vitamin D target notification
    func checkAndSendVitaminDNotification(
        vitaminDData: VitaminDData,
        profile: Profile
    ) async {
        // Only send once per day
        guard !vitaminDTargetNotificationSent else { return }

        let progress = vitaminDData.totalIU / vitaminDData.targetIU

        if progress >= 1.0 {
            await notificationManager.sendVitaminDTargetReachedNotification()

            vitaminDTargetNotificationSent = true
            print("[UVNotificationService] Vitamin D target notification sent")
        }
    }

    // MARK: - Morning UV Peak Notification

    /// Schedule morning UV peak notification
    func scheduleMorningUVPeakNotification(
        peakUVTime: String,
        peakUVIndex: Double
    ) async {
        await notificationManager.scheduleMorningUVPeakNotification(
            peakUVTime: peakUVTime,
            peakUVIndex: peakUVIndex
        )

        print("[UVNotificationService] Morning UV peak notification scheduled for \(peakUVTime)")
    }

    // MARK: - Reset

    /// Reset daily notification state
    func resetDailyState() {
        vitaminDTargetNotificationSent = false
        print("[UVNotificationService] Daily notification state reset")
    }

    /// Reset all notification cooldowns
    func resetCooldowns() {
        lastNotificationTime = Date.distantPast
        lastWarningNotificationTime = Date.distantPast
        lastDangerNotificationTime = Date.distantPast
    }
}
