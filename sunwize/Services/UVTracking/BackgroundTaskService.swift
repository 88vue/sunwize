import Foundation
import BackgroundTasks
import UIKit

// MARK: - Background Task Service

/// Service for iOS background task scheduling and management
@MainActor
class BackgroundTaskService: ObservableObject {
    static let shared = BackgroundTaskService()

    // MARK: - Task Identifiers

    static let uvTrackingTaskIdentifier = "com.sunwize.uvtracking"
    static let dailyMaintenanceTaskIdentifier = "com.sunwize.dailymaintenance"
    static let appRefreshTaskIdentifier = "com.sunwize.apprefresh"

    // MARK: - State

    private var currentBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Callbacks

    var onUVTrackingTask: (() async -> Void)?
    var onDailyMaintenanceTask: (() async -> Void)?
    var onAppRefreshTask: (() async -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Registration

    /// Register all background tasks
    func registerBackgroundTasks() {
        // Register UV tracking task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.uvTrackingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleUVTrackingTask(task: task as! BGProcessingTask)
        }

        // Register daily maintenance task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailyMaintenanceTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleDailyMaintenanceTask(task: task as! BGProcessingTask)
        }

        // Register app refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.appRefreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleAppRefreshTask(task: task as! BGAppRefreshTask)
        }

        print("[BackgroundTaskService] Background tasks registered")
    }

    /// Schedule all background tasks
    func scheduleBackgroundTasks() {
        scheduleUVTrackingTask()
        scheduleDailyMaintenanceTask()
        scheduleAppRefreshTask()
    }

    // MARK: - UV Tracking Task

    func scheduleUVTrackingTask(interval: TimeInterval = 30 * 60) {
        let request = BGProcessingTaskRequest(identifier: Self.uvTrackingTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskService] UV tracking task scheduled for \(Int(interval/60)) minutes")
        } catch {
            print("[BackgroundTaskService] Failed to schedule UV tracking task: \(error)")
        }
    }

    private func handleUVTrackingTask(task: BGProcessingTask) {
        // Schedule next task
        scheduleUVTrackingTask()

        let backgroundTask = Task {
            await onUVTrackingTask?()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Daily Maintenance Task

    func scheduleDailyMaintenanceTask() {
        let request = BGProcessingTaskRequest(identifier: Self.dailyMaintenanceTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        // Schedule for midnight
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day! += 1
        components.hour = 0
        components.minute = 0

        if let scheduledDate = calendar.date(from: components) {
            request.earliestBeginDate = scheduledDate
        }

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskService] Daily maintenance task scheduled")
        } catch {
            print("[BackgroundTaskService] Failed to schedule daily maintenance task: \(error)")
        }
    }

    private func handleDailyMaintenanceTask(task: BGProcessingTask) {
        // Schedule next task
        scheduleDailyMaintenanceTask()

        let backgroundTask = Task {
            await onDailyMaintenanceTask?()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - App Refresh Task

    func scheduleAppRefreshTask(interval: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskService] App refresh task scheduled for \(Int(interval/60)) minutes")
        } catch {
            print("[BackgroundTaskService] Failed to schedule app refresh task: \(error)")
        }
    }

    private func handleAppRefreshTask(task: BGAppRefreshTask) {
        // Schedule next task
        scheduleAppRefreshTask()

        let backgroundTask = Task {
            await onAppRefreshTask?()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            backgroundTask.cancel()
        }
    }

    // MARK: - Foreground Background Task

    /// Begin a background task for continued execution when app backgrounds
    func beginBackgroundTask(name: String = "UVTracking") -> UIBackgroundTaskIdentifier {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endBackgroundTask()
        }

        currentBackgroundTask = taskID
        return taskID
    }

    /// End the current background task
    func endBackgroundTask() {
        if currentBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(currentBackgroundTask)
            currentBackgroundTask = .invalid
        }
    }

    /// Get remaining background time
    var remainingBackgroundTime: TimeInterval {
        return UIApplication.shared.backgroundTimeRemaining
    }
}
