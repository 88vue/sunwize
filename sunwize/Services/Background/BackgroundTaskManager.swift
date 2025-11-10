import Foundation
import BackgroundTasks
import UserNotifications
import CoreLocation
import UIKit

// MARK: - Background Task Manager
/// Manages UV tracking, notifications, and background processing
///
/// CONFIDENCE THRESHOLD PHILOSOPHY (Nov 2025):
/// 
/// PRIMARY GOAL: Avoid false positives (indoor UV notifications) > Missing outdoor time
/// 
/// User experience research shows:
/// - Indoor notification while at desk = HIGHLY ANNOYING → User disables notifications
/// - Missed 30s of outdoor UV tracking = NOT NOTICED → User stays safe
/// 
/// Therefore, we use ASYMMETRIC THRESHOLDS:
/// 
/// START UV TRACKING (Outdoor detection): 0.75 confidence
///   - GPS drift indoors typically produces 0.55-0.70 confidence
///   - Legitimate outdoor (>50m from buildings) produces 0.80+ confidence
///   - Higher threshold filters ~70% of GPS drift false positives
///   - Trade-off: 30-60s delay in outdoor detection (acceptable)
/// 
/// STOP UV TRACKING (Indoor detection): 0.60 confidence
///   - Lower threshold for faster indoor detection
///   - Indoor readings are typically 0.75+ confidence (inside polygon or very close)
///   - Asymmetry prevents "stuck" states where mode oscillates
/// 
/// VEHICLE DETECTION: 0.85 confidence
///   - Safety critical (no UV through windshield)
///   - CoreMotion provides high-confidence automotive activity
///   - Single sample accepted for immediate response
/// 
/// ADDITIONAL SAFETY: Distance check before UV tracking
///   - Even with high confidence, verify >40m from buildings
///   - Catches GPS drift edge cases where confidence calculation missed drift
///   - Final safety net before user gets notification
class BackgroundTaskManager: NSObject {
    static let shared = BackgroundTaskManager()

    // Task identifiers
    static let uvTrackingTaskIdentifier = "com.sunwize.uvtracking"
    static let dailyMaintenanceTaskIdentifier = "com.sunwize.dailymaintenance"
    static let appRefreshTaskIdentifier = "com.sunwize.apprefresh"

    // Services
    private let locationManager = LocationManager.shared
    private let supabase = SupabaseManager.shared
    private let notificationManager = NotificationManager.shared

    // Tracking state
    private var currentSession: UVSession?
    private var lastNotificationTime = Date.distantPast
    private var dailyVitaminD: VitaminDData?
    
    // IMPROVEMENT: Centralized sunscreen state with persistence
    // Published for UI observation, persisted for app restarts
    @Published var sunscreenAppliedTime: Date? {
        didSet {
            // Persist to UserDefaults for survival across app launches
            if let time = sunscreenAppliedTime {
                UserDefaults.standard.set(time.timeIntervalSince1970, forKey: "sunscreen_applied_time")
            } else {
                UserDefaults.standard.removeObject(forKey: "sunscreen_applied_time")
            }
        }
    }
    
    var isSunscreenProtectionActive: Bool {
        guard let appliedTime = sunscreenAppliedTime else { return false }
        return Date().timeIntervalSince(appliedTime) < AppConfig.sunscreenProtectionDuration
    }
    
    // IMPROVED: Asymmetric confidence thresholds for different transition types
    // CRITICAL FIX: Raised to 0.75 to prevent GPS drift false positives (indoor UV notifications)
    // Priority: Avoid annoying users with indoor notifications > missing some outdoor time
    // Analysis: GPS drift indoors typically produces 0.55-0.70 confidence, legitimate outdoor is 0.80+
    private let minConfidenceToStartTracking = 0.75      // OUTSIDE detection (start UV tracking) - RAISED from 0.65
    private let minConfidenceToStopTracking = 0.60       // INSIDE detection (stop UV tracking) - LOWERED from 0.70 for faster indoor detection
    private let minConfidenceForVehicle = 0.85           // VEHICLE detection (immediate stop)
    private let minConfidenceForModeChange = 0.60        // General mode changes
    
    private var lastHandledMode: LocationMode = .unknown
    private var vehicleDetectionSampleCount = 0 // Track consecutive vehicle samples
    
    // Background UV tracking
    private var uvTrackingTimer: Timer?
    private var currentBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        super.init()
        // IMPROVEMENT: Restore sunscreen state from persistence
        if let timestamp = UserDefaults.standard.object(forKey: "sunscreen_applied_time") as? TimeInterval {
            let appliedTime = Date(timeIntervalSince1970: timestamp)
            // Only restore if still within protection window
            if Date().timeIntervalSince(appliedTime) < AppConfig.sunscreenProtectionDuration {
                sunscreenAppliedTime = appliedTime
                print("♻️  [BackgroundTaskManager] Restored sunscreen state: applied \(Int(Date().timeIntervalSince(appliedTime)/60))min ago")
            } else {
                // Expired - clear it
                UserDefaults.standard.removeObject(forKey: "sunscreen_applied_time")
            }
        }
        // Don't register here - let the app call registerBackgroundTasks() explicitly
    }

    // MARK: - Setup

    func registerBackgroundTasks() {
        // Register UV tracking task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.uvTrackingTaskIdentifier,
            using: nil
        ) { task in
            self.handleUVTrackingTask(task: task as! BGProcessingTask)
        }

        // Register daily maintenance task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailyMaintenanceTaskIdentifier,
            using: nil
        ) { task in
            self.handleDailyMaintenanceTask(task: task as! BGProcessingTask)
        }
        
        // Register app refresh task (15-minute fallback checks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.appRefreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefreshTask(task: task as! BGAppRefreshTask)
        }
        
        print("✅ [BackgroundTaskManager] Background tasks registered")
    }

    func scheduleBackgroundTasks() {
        scheduleUVTrackingTask()
        scheduleDailyMaintenanceTask()
        scheduleAppRefreshTask()
    }

    // MARK: - UV Tracking Task

    private func scheduleUVTrackingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.uvTrackingTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        // Schedule based on current UV index
        Task { @MainActor in
            let interval = UVCalculations.getTrackingInterval(for: locationManager.uvIndex)
            request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule UV tracking task: \(error)")
        }
    }

    private func handleUVTrackingTask(task: BGProcessingTask) {
        // Schedule next task
        scheduleUVTrackingTask()

        // Create a background task
        let backgroundTask = Task {
            do {
                // Check if we should track
                guard await shouldTrackUV() else {
                    task.setTaskCompleted(success: true)
                    return
                }

                // Update UV exposure
                try await updateUVExposure()

                // Update Vitamin D
                try await updateVitaminD()

                // Check for notifications
                await checkAndSendNotifications()

                task.setTaskCompleted(success: true)
            } catch {
                print("UV tracking task error: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        // Handle expiration
        task.expirationHandler = {
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
    
    // MARK: - App Refresh Task (15-minute fallback)
    
    private func scheduleAppRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 [BackgroundTaskManager] App refresh task scheduled for 15 minutes")
        } catch {
            print("❌ [BackgroundTaskManager] Failed to schedule app refresh task: \(error)")
        }
    }
    
    private func handleAppRefreshTask(task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleAppRefreshTask()
        
        let backgroundTask = Task {
            // Safety check: verify location tracking is still active
            await MainActor.run {
                if !locationManager.isTracking {
                    print("⚠️ [BackgroundTaskManager] Location tracking stopped - restarting")
                    locationManager.startLocationUpdates()
                }
            }
            
            // Force location check
            _ = try? await locationManager.getCurrentState(forceRefresh: true)
            
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            backgroundTask.cancel()
        }
    }

    // MARK: - Daily Maintenance Task

    private func scheduleDailyMaintenanceTask() {
        let request = BGProcessingTaskRequest(identifier: Self.dailyMaintenanceTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        // Schedule for sunset time (around 8 PM)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 20 // 8 PM
        components.minute = 0

        if let scheduledDate = calendar.date(from: components) {
            request.earliestBeginDate = scheduledDate
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule daily maintenance task: \(error)")
        }
    }

    private func handleDailyMaintenanceTask(task: BGProcessingTask) {
        // Schedule next task
        scheduleDailyMaintenanceTask()

        let backgroundTask = Task {
            do {
                // End any active session
                if let session = currentSession {
                    try await endUVSession(session)
                }

                // Update streaks
                try await updateStreaks()

                // Reset daily counters
                await resetDailyCounters()

                // Send summary notification
                await sendDailySummary()

                task.setTaskCompleted(success: true)
            } catch {
                print("Daily maintenance task error: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            backgroundTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - UV Tracking Logic
    
    /// Helper to check if sunscreen protection is currently active (not expired)
    // Removed - now a computed property above for better encapsulation

    private func shouldTrackUV() async -> Bool {
        // Check if UV tracking is enabled
        guard let userId = await getCurrentUserId(),
              let settings = try? await supabase.getFeatureSettings(userId: userId),
              settings.uvTrackingEnabled else {
            return false
        }

        // Check if it's daytime
        guard isDaytime() else { return false }

        await locationManager.currentLocation // Trigger update
        let mode = await MainActor.run { locationManager.locationMode }
        if mode == .outside {
            let confidence = UserDefaults.standard.double(forKey: "locationManager.confidence")
            return confidence == 0 ? true : confidence >= minConfidenceForModeChange
        }

        if mode == .vehicle {
            return false
        }

        let persistedOutside = UserDefaults.standard.bool(forKey: "locationManager.isOutside")
        let persistedConfidence = UserDefaults.standard.double(forKey: "locationManager.confidence")
        if persistedOutside {
            return persistedConfidence == 0 ? true : persistedConfidence >= minConfidenceForModeChange
        }

        return false
    }

    private func updateUVExposure() async throws {
        guard let userId = await getCurrentUserId(),
              let profile = try? await supabase.getProfile(userId: userId) else {
            return
        }

        // Check if sunscreen protection is active and not expired
        guard !isSunscreenProtectionActive else {
            print("🧴 [BackgroundTaskManager] Sunscreen protection active - skipping UV accumulation")
            return
        }

        // Get or create current session
        if currentSession == nil || currentSession?.isActive == false {
            currentSession = UVSession(
                id: UUID(),
                userId: userId,
                date: Date(),
                startTime: Date(),
                endTime: nil,
                sessionSED: 0,
                sunscreenApplied: false,
                createdAt: Date()
            )
            try await supabase.createUVSession(currentSession!)
        }

        // Calculate SED increment
        let uvIndex = await fetchCurrentUVIndex()
        let interval = Date().timeIntervalSince(currentSession!.startTime)
        let sedIncrement = UVCalculations.calculateSED(uvIndex: uvIndex, exposureSeconds: interval)

        // Update session
        currentSession!.sessionSED += sedIncrement
        try await supabase.updateUVSession(currentSession!)

        // Check exposure ratio
        let exposureRatio = UVCalculations.calculateExposureRatio(
            sessionSED: currentSession!.sessionSED,
            userMED: profile.med
        )

        // Store for notification check
        UserDefaults.standard.set(exposureRatio, forKey: "current_exposure_ratio")
    }

    private func updateVitaminD() async throws {
        guard let userId = await getCurrentUserId(),
              let profile = try? await supabase.getProfile(userId: userId),
              let settings = try? await supabase.getFeatureSettings(userId: userId),
              settings.vitaminDTrackingEnabled else {
            return
        }

        // Get or create today's Vitamin D data
        if dailyVitaminD == nil {
            dailyVitaminD = try await supabase.getVitaminDData(userId: userId, date: Date())
            if dailyVitaminD == nil {
                dailyVitaminD = VitaminDData(
                    id: UUID(),
                    userId: userId,
                    date: Date(),
                    totalIU: 0,
                    targetIU: AppConfig.defaultDailyVitaminDTarget,
                    bodyExposureFactor: 0.3,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        }

        // Skip if sunscreen protection is active and not expired
        guard !isSunscreenProtectionActive else {
            print("🧴 [BackgroundTaskManager] Sunscreen protection active - skipping Vitamin D accumulation")
            return
        }

        // Calculate Vitamin D increment
        let uvIndex = await fetchCurrentUVIndex()
        let interval = min(60, Date().timeIntervalSince(currentSession?.startTime ?? Date()))

        let vitaminDIncrement = VitaminDCalculations.calculateVitaminD(
            uvIndex: uvIndex,
            exposureSeconds: interval,
            bodyExposureFactor: dailyVitaminD!.bodyExposureFactor,
            skinType: profile.skinType,
            latitude: await locationManager.currentLocation?.coordinate.latitude ?? 0,
            date: Date()
        )

        // Update total
        dailyVitaminD!.totalIU += vitaminDIncrement
        try await supabase.updateVitaminDData(dailyVitaminD!)
    }

    // MARK: - Session Management

    /// Called by LocationManager when outdoor mode is detected
    func handleOutsideDetection(location: CLLocation, state: LocationManager.LocationState) async {
        guard state.mode == .outside else {
            await handleInsideDetection(state: state)
            return
        }
        
        // Check if it's daytime - don't start UV tracking at night
        guard isDaytime() else {
            print("🌙 [BackgroundTaskManager] Outside detected but it's nighttime - no UV tracking needed")
            await handleInsideDetection(state: state) // Stop any running UV tracking
            return
        }
        
        // PRIORITY 7 FIX: Use startup-adjusted thresholds
        let thresholds = await locationManager.getConfidenceThresholds()
        let minConfidence = thresholds.uvStart

        guard state.confidence >= minConfidence else {
            let startupNote = await locationManager.isInStartupPhase ? " (startup phase)" : ""
            print("⚠️ [BackgroundTaskManager] Outside detected but confidence too low (\(String(format: "%.2f", state.confidence)) < \(String(format: "%.2f", minConfidence)))\(startupNote)")
            return
        }
        
        // FIX #4: Additional safety check - verify distance from buildings before starting UV tracking
        // This catches GPS drift cases where confidence is high but user is actually indoors near window
        if let nearestDistance = await getNearestBuildingDistance(state: state) {
            if nearestDistance < 40 {
                print("⚠️ [BackgroundTaskManager] Outside detected but too close to building (\(Int(nearestDistance))m) - likely GPS drift, ignoring")
                return
            } else {
                print("✅ [BackgroundTaskManager] Distance safety check passed: \(Int(nearestDistance))m from nearest building")
            }
        }
        
        if lastHandledMode != .outside {
            DetectionLogger.logUVTracking(
                action: "START",
                mode: .outside,
                confidence: state.confidence,
                uvIndex: nil,
                reason: "Outdoor detection confirmed"
            )
        }

        if uvTrackingTimer == nil {
            await startUVTrackingTimer()
        }

        lastHandledMode = .outside
        try? await updateUVExposure()
    }
    
    /// Get nearest building distance for safety checks (prevents GPS drift false positives)
    private func getNearestBuildingDistance(state: LocationManager.LocationState) async -> Double? {
        do {
            let buildings = try await OverpassService.shared.getNearbyBuildings(
                latitude: state.latitude,
                longitude: state.longitude
            )
            let distance = GeometryUtils.nearestBuildingDistance(
                point: [state.latitude, state.longitude],
                buildings: buildings
            )
            return distance < 999999 ? distance : nil // Filter out "no buildings found" sentinel
        } catch {
            print("⚠️ [BackgroundTaskManager] Failed to get building distance for safety check: \(error)")
            return nil // On error, allow the transition (fail open for better UX)
        }
    }
    
    /// Called by LocationManager when indoor/vehicle mode is detected
    func handleInsideDetection(state: LocationManager.LocationState) async {
        if state.mode == .unknown {
            if lastHandledMode != .unknown {
                let reasonDescription = state.uncertaintyReason?.rawValue.replacingOccurrences(of: "_", with: " ") ?? "unspecified"
                print("❔ [BackgroundTaskManager] Location uncertain (reason: \(reasonDescription)) - pausing UV tracking")
            }
            await stopUVTrackingTimer()
            if let session = currentSession {
                try? await endUVSession(session)
            }
            lastHandledMode = .unknown
            vehicleDetectionSampleCount = 0
            return
        }

        // IMPROVED: Asymmetric threshold for vehicle detection (higher confidence, immediate action)
        if state.mode == .vehicle {
            // Vehicle detection requires high confidence but acts immediately (safety critical)
            guard state.confidence >= minConfidenceForVehicle else {
                print("⚠️ [BackgroundTaskManager] Vehicle detected but confidence too low (\(String(format: "%.2f", state.confidence)) < \(String(format: "%.2f", minConfidenceForVehicle)))")
                vehicleDetectionSampleCount = 0
                return
            }
            
            if lastHandledMode == .vehicle {
                vehicleDetectionSampleCount += 1
                return
            }
            
            // Single high-confidence sample is enough for vehicle detection (no UV through windshield)
            DetectionLogger.logUVTracking(
                action: "STOP",
                mode: .vehicle,
                confidence: state.confidence,
                reason: "Vehicle detection - immediate stop (safety critical)"
            )

            await stopUVTrackingTimer()
            if let session = currentSession {
                try? await endUVSession(session)
            }
            lastHandledMode = .vehicle
            vehicleDetectionSampleCount = 1
            return
        }
        
        // Reset vehicle counter when not in vehicle mode
        vehicleDetectionSampleCount = 0

        // PRIORITY 7 FIX: Use startup-adjusted thresholds
        let thresholds = await locationManager.getConfidenceThresholds()
        let requiredConfidence = thresholds.uvStop

        guard state.confidence >= requiredConfidence else {
            let startupNote = await locationManager.isInStartupPhase ? " (startup phase)" : ""
            print("⚠️ [BackgroundTaskManager] Ignoring \(state.mode.rawValue) transition due to low confidence (\(String(format: "%.2f", state.confidence)))\(startupNote)")
            return
        }
        
        if lastHandledMode == .inside {
            return
        }
        
        DetectionLogger.logUVTracking(
            action: "STOP",
            mode: .inside,
            confidence: state.confidence,
            reason: "Indoor detection confirmed"
        )

        await stopUVTrackingTimer()
        if let session = currentSession {
            try? await endUVSession(session)
        }
        lastHandledMode = .inside
    }
    
    /// Called every 30 seconds from LocationManager background processing
    func handleBackgroundLocationUpdate(state: LocationManager.LocationState) async {
        if state.mode == .vehicle {
            await handleInsideDetection(state: state)
            return
        }
        
        guard state.mode == .outside else {
            await handleInsideDetection(state: state)
            return
        }
        
        guard state.confidence >= minConfidenceForModeChange else {
            print("⚠️ [BackgroundTaskManager] Background update skipped due to low confidence (\(String(format: "%.2f", state.confidence)))")
            return
        }
        
        lastHandledMode = .outside
        
        try? await updateUVExposure()
        try? await updateVitaminD()
        await checkAndSendNotifications()
    }
    
    /// Start timer-based UV tracking (runs in background)
    private func startUVTrackingTimer() async {
        guard uvTrackingTimer == nil else { return }
        
        await MainActor.run {
            print("🌞 [BackgroundTaskManager] Starting UV tracking timer (background mode)")
            
            // Create background task
            currentBackgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                Task {
                    await self?.stopUVTrackingTimer()
                }
            }
            
            // Get adaptive interval based on UV index
            let interval = UVCalculations.getTrackingInterval(for: locationManager.uvIndex)
            
            // Create timer
            uvTrackingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task {
                    try? await self?.updateUVExposure()
                    try? await self?.updateVitaminD()
                    await self?.checkAndSendNotifications()
                    
                    // Renew background task
                    await MainActor.run {
                        if let self = self, self.currentBackgroundTask != .invalid {
                            UIApplication.shared.endBackgroundTask(self.currentBackgroundTask)
                            self.currentBackgroundTask = UIApplication.shared.beginBackgroundTask {
                                Task {
                                    await self.stopUVTrackingTimer()
                                }
                            }
                        }
                    }
                }
            }
            
            // Add to common run loop so it runs in background
            if let timer = uvTrackingTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
        }
    }
    
    /// Stop UV tracking timer
    private func stopUVTrackingTimer() async {
        await MainActor.run {
            print("🌙 [BackgroundTaskManager] Stopping UV tracking timer")
            
            uvTrackingTimer?.invalidate()
            uvTrackingTimer = nil
            
            if currentBackgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundTask)
                currentBackgroundTask = .invalid
            }
        }
    }

    func startUVSession() async throws {
        guard let userId = await getCurrentUserId() else { return }

        // End any existing session
        if let existingSession = currentSession {
            try await endUVSession(existingSession)
        }

        // Create new session
        currentSession = UVSession(
            id: UUID(),
            userId: userId,
            date: Date(),
            startTime: Date(),
            endTime: nil,
            sessionSED: 0,
            sunscreenApplied: false,
            createdAt: Date()
        )

        try await supabase.createUVSession(currentSession!)
    }

    func endUVSession(_ session: UVSession) async throws {
        var endedSession = session
        endedSession.endTime = Date()
        try await supabase.updateUVSession(endedSession)
        currentSession = nil
    }

    func applySunscreen() async {
        sunscreenAppliedTime = Date()

        // End current session and mark as sunscreen applied
        if var session = currentSession {
            session.sunscreenApplied = true
            session.endTime = Date()
            try? await supabase.updateUVSession(session)
        }

        // Start new session
        try? await startUVSession()
        
        // Schedule reapplication reminder
        await NotificationManager.shared.scheduleSunscreenReapplicationReminder(
            after: AppConfig.sunscreenProtectionDuration
        )
        
        print("🧴 [BackgroundTaskManager] Sunscreen applied - protection active for 2 hours")
    }

    // MARK: - Streaks

    private func updateStreaks() async throws {
        guard let userId = await getCurrentUserId(),
              let profile = try? await supabase.getProfile(userId: userId) else {
            return
        }

        // Get today's sessions
        let sessions = try await supabase.getUserSessions(userId: userId, date: Date())

        // Check UV safe streak
        let totalSED = sessions.reduce(0) { $0 + $1.sessionSED }
        let medInSED = Double(profile.med) / 100.0
        let isUVSafe = totalSED < medInSED

        // Check Vitamin D streak
        let vitaminDReached = dailyVitaminD?.targetReached ?? false

        // Update streaks
        if var streaks = try await supabase.getStreaks(userId: userId) {
            if isUVSafe {
                streaks.uvSafeStreak += 1
            } else {
                streaks.uvSafeStreak = 0
            }

            if vitaminDReached {
                streaks.vitaminDStreak += 1
            } else {
                streaks.vitaminDStreak = 0
            }

            try await supabase.updateStreaks(streaks)
        }
    }

    // MARK: - Notifications

    private func checkAndSendNotifications() async {
        guard let exposureRatio = UserDefaults.standard.object(forKey: "current_exposure_ratio") as? Double else {
            return
        }

        let now = Date()
        let timeSinceLastNotification = now.timeIntervalSince(lastNotificationTime)

        // Warning at 75% MED
        if exposureRatio >= AppConfig.uvWarningThreshold && exposureRatio < AppConfig.uvDangerThreshold {
            if timeSinceLastNotification > AppConfig.notificationCooldown {
                await notificationManager.sendUVWarningNotification(exposureRatio: exposureRatio)
                lastNotificationTime = now
            }
        }

        // Danger at 100% MED
        if exposureRatio >= AppConfig.uvDangerThreshold {
            // Bypass cooldown for danger notifications
            await notificationManager.sendUVDangerNotification(exposureRatio: exposureRatio)
            lastNotificationTime = now
        }

        // Vitamin D target reached
        if dailyVitaminD?.targetReached == true {
            let hasNotifiedToday = UserDefaults.standard.bool(forKey: "vitamin_d_notified_\(dateKey())")
            if !hasNotifiedToday {
                await notificationManager.sendVitaminDTargetReachedNotification()
                UserDefaults.standard.set(true, forKey: "vitamin_d_notified_\(dateKey())")
            }
        }
    }

    private func sendDailySummary() async {
        // Send daily summary notification
        guard let userId = await getCurrentUserId() else { return }

        let sessions = try? await supabase.getUserSessions(userId: userId, date: Date())
        let totalSED = sessions?.reduce(0) { $0 + $1.sessionSED } ?? 0
        let vitaminD = dailyVitaminD?.totalIU ?? 0

        await notificationManager.sendDailySummaryNotification(
            totalSED: totalSED,
            vitaminDIU: vitaminD
        )
    }

    // MARK: - Helpers

    private func getCurrentUserId() async -> UUID? {
        // Get from auth service or stored credentials
        guard let userIdString = UserDefaults.standard.string(forKey: "user_id"),
              let userId = UUID(uuidString: userIdString) else {
            return nil
        }
        return userId
    }

    private func isDaytime() -> Bool {
        // Use centralized daytime service
        return DaytimeService.shared.isDaytime
    }

    private func fetchCurrentUVIndex() async -> Double {
        // This would fetch from the weather service
        // For now, return the cached value
        return await locationManager.uvIndex
    }

    private func resetDailyCounters() async {
        dailyVitaminD = nil
        currentSession = nil
        sunscreenAppliedTime = nil
    }

    private func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
