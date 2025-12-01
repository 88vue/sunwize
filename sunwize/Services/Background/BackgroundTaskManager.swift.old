import Foundation
import BackgroundTasks
import UserNotifications
import CoreLocation
import UIKit

// MARK: - Background Task Manager
/// Manages UV tracking, notifications, and background processing
///
/// CONFIDENCE THRESHOLD & OUTDOOR TRACKING LOCK PHILOSOPHY (Nov 2025):
///
/// PRIMARY GOAL: Avoid false positives (indoor UV notifications) > Missing outdoor time
/// SECONDARY GOAL: Stable outdoor tracking (no flip-flopping when walking past buildings)
///
/// User experience research shows:
/// - Indoor notification while at desk = HIGHLY ANNOYING → User disables notifications
/// - UV tracking resetting every 30s when walking = DEFEATS PURPOSE → Cannot track total exposure
/// - Missed 30-60s of outdoor UV tracking = NOT NOTICED → User stays safe
///
/// Therefore, we use THREE-TIER STATE MACHINE with ASYMMETRIC THRESHOLDS:
///
/// TIER 1: START UV TRACKING (Outdoor detection) - VERY CONSERVATIVE
///   - Requires: 0.90 confidence (0.92 during startup phase - reduced for beach/park starts)
///   - Polygon-based: Must NOT be inside building polygon (absolute veto)
///   - Distance check: >40m from buildings OR recent polygon exit OR clear outdoor evidence:
///     * Clear outdoor = walking + excellent GPS (<25m) + very high confidence (≥0.92)
///     * Enables urban sidewalk tracking while preventing GPS drift false positives
///   - Daytime only (no UV tracking at night)
///   - Once started: ACTIVATES OUTDOOR TRACKING LOCK
///   - Trade-off: 60-90s delay in outdoor detection (acceptable)
///
/// TIER 2: MAINTAIN UV TRACKING (Outdoor lock active) - STABLE & STICKY
///   - Ignores: Distance oscillations, confidence variations, weak indoor signals
///   - Maintains: Outdoor state for continuous UV accumulation
///   - Purpose: Prevents flip-flopping when walking on sidewalk past multiple buildings
///   - Only strong signals can break lock (polygon entry, floor, vehicle)
///
/// TIER 3: STOP UV TRACKING (Indoor detection) - RESPONSIVE TO STRONG SIGNALS
///   - When lock active: Requires STRONG indoor signal:
///     * Sustained polygon occupancy (>30s inside building boundary)
///     * Floor detection (multi-story building confirmation)
///     * Vehicle detection (0.85+ confidence, safety critical)
///     * Stationary near building >3 minutes
///   - When lock inactive: Requires 0.70 confidence
///   - On stop: RELEASES outdoor lock, ready for next outdoor session
///
/// POLYGON-BASED GEOFENCING: Exact building boundaries (not circular approximations)
///   - Uses OSM building polygons for precise entry/exit detection
///   - Polygon entry = absolute veto for outdoor start
///   - Polygon exit = strong evidence for outdoor (overrides distance check)
@MainActor
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
    private var lastSEDUpdateTime: Date?  // Track last SED update to calculate increments
    private var lastUVIndexFetchTime: Date?  // Track UV index freshness
    private var cachedUVIndex: Double = 0.0  // Store fetched UV index between updates
    private var lastKnownDate: Date?  // Track for day change detection
    
    // UPDATED CONFIDENCE THRESHOLDS (Nov 2025 - Outdoor Tracking Lock System)
    // NOTE: Start/stop thresholds now implemented directly in handleOutsideDetection/handleInsideDetection
    // with outdoor tracking lock logic. These constants kept for vehicle detection compatibility.
    private let minConfidenceForVehicle = 0.85           // VEHICLE detection (immediate stop, safety critical)
    private let minConfidenceForModeChange = 0.60        // General mode changes (background updates)
    
    private var lastHandledMode: LocationMode = .unknown
    private var vehicleDetectionSampleCount = 0 // Track consecutive vehicle samples

    // OUTDOOR TRACKING LOCK: State machine for stable outdoor UV tracking
    // Once outdoor tracking starts, maintains outdoor state until strong indoor signals detected
    // Prevents flip-flopping when walking on sidewalk past multiple buildings
    private var isOutdoorTrackingLocked: Bool = false
    private var outdoorLockStartTime: Date?
    private var lastOutsideDetectionTime: Date?
    private var unknownHoldStartTime: Date?

    var outdoorLockActive: Bool { isOutdoorTrackingLocked }

    // VEHICLE TRACKING LOCK: State machine for stable vehicle detection
    // Once vehicle confirmed (0.85+ confidence), maintains vehicle state until parking detected
    // Prevents flip-flopping between vehicle/outside during stop-and-go city driving
    private var isVehicleTrackingLocked: Bool = false
    private var vehicleLockStartTime: Date?
    private var lastVehicleDetectionTime: Date?

    var vehicleLockActive: Bool { isVehicleTrackingLocked }

    // Sunscreen state tracking (synced with UserDefaults)
    private var sunscreenStateKey = "sunscreenActive"
    private var sunscreenTimeKey = "sunscreenAppliedTime"

    // Background UV tracking
    private var uvTrackingTimer: Timer?
    private var currentBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @Published var isUVTrackingActive: Bool = false

    // Published session state for frontend synchronization (single source of truth)
    @Published private(set) var currentSessionSED: Double = 0.0
    @Published private(set) var currentSessionStartTime: Date?
    @Published private(set) var currentExposureRatio: Double = 0.0
    @Published private(set) var currentVitaminD: Double = 0.0
    @Published private(set) var vitaminDProgress: Double = 0.0

    private override init() {
        super.init()
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
            let interval: TimeInterval = isUVTrackingActive
                ? UVCalculations.getTrackingInterval(for: locationManager.uvIndex)
                : 15 * 60
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

                // Note: Notifications are sent within updateUVExposure() and updateVitaminD()

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

        // Schedule for midnight (12 AM) - daily reset time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 0  // 12 AM (midnight)
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

                // Save final vitamin D total to database before reset
                if let vitaminDData = dailyVitaminD {
                    try await supabase.updateVitaminDData(vitaminDData)
                    print("💊 [BackgroundTaskManager] Saved final Vitamin D total: \(String(format: "%.1f", vitaminDData.totalIU)) IU before midnight reset")
                }

                // Update streaks
                try await updateStreaks()

                // Reset daily counters
                await resetDailyCounters()

                // Schedule tomorrow's morning UV peak notification
                await scheduleMorningUVNotification()

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

    private func scheduleMorningUVNotification() async {
        // Get tomorrow's UV forecast
        guard let location = await locationManager.currentLocation else {
            print("⚠️ [BackgroundTaskManager] Cannot schedule morning notification: No location available")
            return
        }

        do {
            // Fetch UV forecast
            let forecast = try await WeatherService.shared.getUVForecast(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            // Filter to tomorrow's forecast
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let tomorrowStart = calendar.startOfDay(for: tomorrow)
            let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart

            let tomorrowForecast = forecast.filter { $0.time >= tomorrowStart && $0.time < tomorrowEnd }

            // Find peak UV index and time
            if let peakData = tomorrowForecast.max(by: { $0.uvIndex < $1.uvIndex }) {
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                let peakTimeString = timeFormatter.string(from: peakData.time)

                // Schedule the notification
                await notificationManager.scheduleMorningUVPeakNotification(
                    peakUVTime: peakTimeString,
                    peakUVIndex: peakData.uvIndex
                )

                print("✅ [BackgroundTaskManager] Morning UV peak notification scheduled: Peak \(String(format: "%.1f", peakData.uvIndex)) at \(peakTimeString)")
            } else {
                print("⚠️ [BackgroundTaskManager] No forecast data available for tomorrow")
            }
        } catch {
            print("❌ [BackgroundTaskManager] Failed to schedule morning notification: \(error)")
        }
    }

    // MARK: - UV Tracking Logic

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
        // GUARD: Only update if UV tracking is active
        guard isUVTrackingActive else {
            print("⚠️ [BackgroundTaskManager] UV update skipped - tracking not active")
            return
        }

        // GUARD: Only update if outdoor lock is active (the authoritative source of outdoor state)
        // NOTE: Don't check locationMode (UI mode) - it intentionally lags behind actual detection
        guard isOutdoorTrackingLocked else {
            print("⚠️ [BackgroundTaskManager] UV update skipped - outdoor lock not active")
            return
        }

        guard let userId = await getCurrentUserId(),
              let profile = try? await supabase.getProfile(userId: userId) else {
            return
        }

        // Get or create current session
        if currentSession == nil || currentSession?.isActive == false {
            let sunscreenActive = isSunscreenActive()
            let sessionStart = Date()
            currentSession = UVSession(
                id: UUID(),
                userId: userId,
                date: sessionStart,
                startTime: sessionStart,
                endTime: nil,
                sessionSED: 0,
                sunscreenApplied: sunscreenActive,
                createdAt: sessionStart
            )
            try await supabase.createUVSession(currentSession!)

            // Initialize tracking timestamps
            lastSEDUpdateTime = sessionStart
            lastUVIndexFetchTime = nil  // Force fresh fetch on first update

            // Publish session start time to frontend
            await MainActor.run {
                currentSessionStartTime = sessionStart
                currentSessionSED = 0.0
                currentExposureRatio = 0.0
            }

            if sunscreenActive {
                print("☀️ [BackgroundTaskManager] Session started with sunscreen protection active")
            }
            print("📊 [BackgroundTaskManager] New UV session created - ID: \(currentSession!.id)")
        }

        // Fetch UV index (refresh if stale)
        let uvIndex = await fetchCurrentUVIndexWithRefresh()

        // Calculate SED increment SINCE LAST UPDATE (not full session duration)
        // This prevents exponential growth bug
        let now = Date()
        let interval: TimeInterval
        if let lastUpdate = lastSEDUpdateTime {
            interval = now.timeIntervalSince(lastUpdate)
        } else {
            // Fallback if lastUpdateTime wasn't set (shouldn't happen)
            interval = now.timeIntervalSince(currentSession!.startTime)
            print("⚠️ [BackgroundTaskManager] lastSEDUpdateTime was nil, using session start time")
        }

        // Calculate increment for this interval only
        let sedIncrement = UVCalculations.calculateSED(uvIndex: uvIndex, exposureSeconds: interval)

        // Update session with increment
        currentSession!.sessionSED += sedIncrement
        lastSEDUpdateTime = now

        print("📈 [BackgroundTaskManager] UV Update - Interval: \(Int(interval))s, UV: \(String(format: "%.1f", uvIndex)), SED +\(String(format: "%.4f", sedIncrement)) → Total: \(String(format: "%.4f", currentSession!.sessionSED))")

        try await supabase.updateUVSession(currentSession!)

        // Calculate exposure ratio
        let exposureRatio = UVCalculations.calculateExposureRatio(
            sessionSED: currentSession!.sessionSED,
            userMED: profile.med
        )

        // Publish to frontend (single source of truth)
        await MainActor.run {
            currentSessionSED = currentSession!.sessionSED
            currentExposureRatio = exposureRatio
        }

        // Store for notification check
        UserDefaults.standard.set(exposureRatio, forKey: "current_exposure_ratio")

        // Send notifications based on exposure thresholds
        await checkAndSendUVNotifications(exposureRatio: exposureRatio, profile: profile)
    }

    private func updateVitaminD() async throws {
        // Check for day change first (handles midnight reset)
        await checkForDayChange()

        // GUARD: Only update if UV tracking is active
        guard isUVTrackingActive else {
            print("⚠️ [BackgroundTaskManager] Vitamin D update skipped - tracking not active")
            return
        }

        // GUARD: Only update if location is definitely outside
        guard await locationManager.locationMode == .outside else {
            print("⚠️ [BackgroundTaskManager] Vitamin D update skipped - not outside (mode: \(await locationManager.locationMode.rawValue))")
            return
        }

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
                // Create new record for today
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

                // CRITICAL: Save new record to database
                try await supabase.createVitaminDData(dailyVitaminD!)
                print("💊 [BackgroundTaskManager] Created new Vitamin D record for today")
            }

            // Publish initial values to frontend
            let initialProgress = dailyVitaminD!.totalIU / dailyVitaminD!.targetIU
            await MainActor.run {
                currentVitaminD = dailyVitaminD!.totalIU
                vitaminDProgress = initialProgress
            }
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

        // Update total (in-memory only - database sync happens at midnight and session end)
        dailyVitaminD!.totalIU += vitaminDIncrement
        dailyVitaminD!.updatedAt = Date()
        // NOTE: Removed continuous database sync - now only syncs at:
        // 1. Midnight (handleDailyMaintenanceTask)
        // 2. Session end (endUVSession)
        // 3. App backgrounding (syncVitaminDToDatabase)

        // Publish to frontend (single source of truth)
        let progress = dailyVitaminD!.totalIU / dailyVitaminD!.targetIU
        await MainActor.run {
            currentVitaminD = dailyVitaminD!.totalIU
            vitaminDProgress = progress
        }

        print("💊 [BackgroundTaskManager] Vitamin D Update - Increment: +\(String(format: "%.1f", vitaminDIncrement)) IU → Total: \(String(format: "%.1f", dailyVitaminD!.totalIU)) IU (\(String(format: "%.0f", progress * 100))% of target)")

        // Check if daily target reached
        await checkAndSendVitaminDNotification(vitaminDData: dailyVitaminD!, profile: profile)
    }

    // MARK: - Session Management

    /// Called by LocationManager when outdoor mode is detected
    /// Implements three-tier logic: Hard to start, sticky during tracking, responsive to strong signals
    func handleOutsideDetection(location: CLLocation, state: LocationManager.LocationState) async {
        // Check manual override first - if active, treat as inside
        if await locationManager.isManualOverrideActive {
            print("🏠 [BackgroundTaskManager] Manual override active - treating as inside")

            // If UV tracking is active, stop it
            if isUVTrackingActive {
                await stopUVTrackingTimer()
                if let session = currentSession {
                    try? await endUVSession(session)
                }
            }

            // Release outdoor lock if active
            if isOutdoorTrackingLocked {
                isOutdoorTrackingLocked = false
                outdoorLockStartTime = nil
                print("🔓 [BackgroundTaskManager] Outdoor lock RELEASED (manual override)")
            }

            lastHandledMode = .inside
            return
        }

        guard state.mode == .outside else {
            await handleInsideDetection(state: state)
            return
        }

        // CRITICAL FIX: Check vehicle lock BEFORE processing outdoor detection
        // This prevents flip-flopping where vehicle mode briefly detected but then outdoor
        // takes over because vehicle confidence was in the gap (0.80-0.85) or at red lights
        if isVehicleTrackingLocked {
            let lockDuration = vehicleLockStartTime.map { Date().timeIntervalSince($0) } ?? 0
            print("🚗🔒 [BackgroundTaskManager] Vehicle lock active (\(Int(lockDuration))s) - blocking outdoor classification")
            lastHandledMode = .vehicle
            return
        }

        // Check if it's daytime - don't start UV tracking at night
        guard isDaytime() else {
            print("🌙 [BackgroundTaskManager] Outside detected but it's nighttime - no UV tracking needed")
            await handleInsideDetection(state: state) // Stop any running UV tracking
            return
        }

        // TIER 2: DURING UV TRACKING (LOCKED) - Maintain outdoor state, ignore oscillations
        if isOutdoorTrackingLocked {
            // Already tracking UV, maintain outdoor state regardless of distance/confidence variations
            // Only strong indoor signals (polygon entry, floor, vehicle) can break the lock
            if let lockTime = outdoorLockStartTime {
                let duration = Date().timeIntervalSince(lockTime)
                print("🔒 [BackgroundTaskManager] Outdoor lock active (\(Int(duration))s) - maintaining UV tracking")
            }

            lastHandledMode = .outside
            lastOutsideDetectionTime = Date()
            unknownHoldStartTime = nil
            try? await updateUVExposure()
            return
        }

        // TIER 1: STARTING UV TRACKING (NOT LOCKED) - Very conservative validation
        print("🎯 [BackgroundTaskManager] Evaluating outdoor start conditions (lock not active)")

        // Require high confidence to start (0.85)
        // FIX (Nov 2025): Removed startup penalty - polygon veto already prevents indoor false starts
        // The polygon check is the primary safety mechanism, additional confidence penalty was causing
        // 10-20 second delays in legitimate outdoor detection during first 2 minutes
        let requiredConfidence = 0.85

        guard state.confidence >= requiredConfidence else {
            print("⚠️ [BackgroundTaskManager] Outside detected but confidence too low (\(String(format: "%.2f", state.confidence)) < \(String(format: "%.2f", requiredConfidence)))")
            return
        }

        // FAST PATH: Sustained excellent GPS override
        // If GPS has been excellent (<12m) for 60+ seconds while walking and NOT in polygon,
        // this is extremely strong outdoor evidence - bypass distance checks
        let sustainedGPS = await locationManager.checkSustainedExcellentGPS()
        let hasWalkingActivity = state.activity == .walking || state.activity == .running
        let notInsidePolygon = await !locationManager.isInsideAnyPolygon()

        if sustainedGPS.hasExcellent && sustainedGPS.duration >= 45 && hasWalkingActivity && notInsidePolygon {
            print("✅ FAST PATH: Sustained excellent GPS (\(String(format: "%.1f", sustainedGPS.avgAccuracy))m avg for \(Int(sustainedGPS.duration))s) + walking + not in polygon")
            // Skip distance safety check - excellent GPS for this long is definitive outdoor
        } else {
            // Normal path: Distance safety check with contextual evaluation
            let (hasPolygonExit, exitTime) = await locationManager.hasRecentPolygonExit()

            if let nearestDistance = await getNearestBuildingDistance(state: state) {
                if nearestDistance < 25 {
                    // Close to building - check for clear outdoor evidence
                    let hasWalkingMotion = state.activity == .walking || state.activity == .running
                    let hasGoodGPS = (state.accuracy ?? 100) < 30
                    // FIX (Nov 2025): Lowered to 0.85 to match MODERATE OUTDOOR accuracy pattern
                    // The accuracy pattern returns exactly 0.85 for walking+moderate GPS
                    let hasHighConfidence = state.confidence >= 0.85

                    // Allow if: polygon exit OR (walking + good GPS + high confidence)
                    if hasPolygonExit {
                        print("✅ Close to building (\(Int(nearestDistance))m) + polygon exit - outdoor start allowed")
                    } else if hasWalkingMotion && hasGoodGPS && hasHighConfidence {
                        print("✅ Close to building (\(Int(nearestDistance))m) + walking + good GPS - sidewalk detected")
                    } else {
                        print("⚠️ Too close to building (\(Int(nearestDistance))m) without clear outdoor evidence - blocking")
                        return
                    }
                }
            }
        }

        // All checks passed - START UV tracking and ACTIVATE lock
        DetectionLogger.logUVTracking(
            action: "START",
            mode: .outside,
            confidence: state.confidence,
            uvIndex: nil,
            reason: "Outdoor detection confirmed"
        )

        // CRITICAL FIX: Activate lock FIRST, then start timer (prevents race condition)
        // Previously timer started first, creating a window where timer fires but lock isn't active yet
        // ACTIVATE OUTDOOR TRACKING LOCK
        isOutdoorTrackingLocked = true
        outdoorLockStartTime = Date()
        lastOutsideDetectionTime = Date()
        unknownHoldStartTime = nil
        print("🔒 [BackgroundTaskManager] OUTDOOR LOCK ACTIVATED - will maintain outdoor state until strong indoor signal")

        // Start timer AFTER lock is active (atomic operation)
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
    /// Respects outdoor tracking lock - requires strong signals to stop UV tracking
    func handleInsideDetection(state: LocationManager.LocationState) async {
        if state.mode == .unknown {
            let now = Date()
            let recentOutside = {
                if let t = lastOutsideDetectionTime { return now.timeIntervalSince(t) < AppConfig.unknownHoldDebounce }
                return false
            }()

            if isOutdoorTrackingLocked {
                if recentOutside {
                    lastHandledMode = .unknown
                    return
                }

                if unknownHoldStartTime == nil {
                    unknownHoldStartTime = now
                    await stopUVTrackingTimer()
                    lastHandledMode = .unknown
                    return
                }

                let elapsed = now.timeIntervalSince(unknownHoldStartTime!)
                if elapsed < AppConfig.unknownHoldDebounce {
                    lastHandledMode = .unknown
                    return
                }

                await stopUVTrackingTimer()
                if let session = currentSession { try? await endUVSession(session) }
                isOutdoorTrackingLocked = false
                outdoorLockStartTime = nil
                unknownHoldStartTime = nil
                lastHandledMode = .unknown
                vehicleDetectionSampleCount = 0
                return
            }

            if lastHandledMode != .unknown {
                let reasonDescription = state.uncertaintyReason?.rawValue.replacingOccurrences(of: "_", with: " ") ?? "unspecified"
                print("❔ [BackgroundTaskManager] Location uncertain (reason: \(reasonDescription)) - pausing UV tracking")
            }
            await stopUVTrackingTimer()
            if let session = currentSession { try? await endUVSession(session) }
            isOutdoorTrackingLocked = false
            outdoorLockStartTime = nil
            lastHandledMode = .unknown
            vehicleDetectionSampleCount = 0
            return
        }

        // IMPROVED: Vehicle detection with tracking lock (Phase 1 Fix #2)
        if state.mode == .vehicle {
            // Vehicle detection requires high confidence but acts immediately (safety critical)
            guard state.confidence >= minConfidenceForVehicle else {
                print("⚠️ [BackgroundTaskManager] Vehicle detected but confidence too low (\(String(format: "%.2f", state.confidence)) < \(String(format: "%.2f", minConfidenceForVehicle)))")
                vehicleDetectionSampleCount = 0
                return
            }

            // Update last vehicle detection time for lock maintenance
            lastVehicleDetectionTime = Date()

            if lastHandledMode == .vehicle {
                vehicleDetectionSampleCount += 1

                // Maintain vehicle lock if active
                if isVehicleTrackingLocked {
                    if let lockTime = vehicleLockStartTime {
                        let duration = Date().timeIntervalSince(lockTime)
                        print("🚗🔒 [BackgroundTaskManager] Vehicle lock active (\(Int(duration))s) - maintaining vehicle state")
                    }
                }
                return
            }

            // First vehicle detection - activate vehicle lock
            // MUTUAL EXCLUSION: Ensure outdoor lock is released before activating vehicle lock
            if !isVehicleTrackingLocked {
                // Release outdoor lock first (prevent dual-lock state)
                if isOutdoorTrackingLocked {
                    isOutdoorTrackingLocked = false
                    outdoorLockStartTime = nil
                    print("🔓 [BackgroundTaskManager] Outdoor lock RELEASED (entering vehicle mode)")
                }

                isVehicleTrackingLocked = true
                vehicleLockStartTime = Date()
                print("🚗🔒 [BackgroundTaskManager] Vehicle lock ACTIVATED (confidence: \(String(format: "%.2f", state.confidence)))")
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

            // Release outdoor lock on vehicle detection (strong signal)
            // Note: This is a safety check - outdoor lock should already be released by mutual exclusion above
            // Keeping this as defensive programming in case code flow changes
            if isOutdoorTrackingLocked {
                isOutdoorTrackingLocked = false
                outdoorLockStartTime = nil
                print("🔓 [BackgroundTaskManager] Outdoor lock RELEASED (vehicle detection - fallback)")
            }

            lastHandledMode = .vehicle
            vehicleDetectionSampleCount = 1
            return
        }

        // Reset vehicle counter when not in vehicle mode
        vehicleDetectionSampleCount = 0

        // VEHICLE LOCK MAINTENANCE: Check if we should maintain or release vehicle lock
        if isVehicleTrackingLocked {
            let parked = await isDefinitelyParked(state: state)
            if parked {
                // Parking confirmed - release vehicle lock
                isVehicleTrackingLocked = false
                let lockDuration = vehicleLockStartTime.map { Date().timeIntervalSince($0) } ?? 0
                vehicleLockStartTime = nil
                lastVehicleDetectionTime = nil
                print("🚗🔓 [BackgroundTaskManager] Vehicle lock RELEASED (parking detected after \(Int(lockDuration))s)")
                // Continue to normal indoor/outdoor classification below
            } else {
                // Still in vehicle (stop-and-go, red light, etc.) - maintain vehicle state
                if let lockTime = vehicleLockStartTime {
                    let duration = Date().timeIntervalSince(lockTime)
                    print("🚗🔒 [BackgroundTaskManager] Vehicle lock active (\(Int(duration))s) - ignoring reclassification to \(state.mode.rawValue)")
                }
                // Stay in vehicle mode, ignore outdoor/indoor classification
                lastHandledMode = .vehicle
                return
            }
        }

        // TIER 3: STOPPING UV TRACKING - Require STRONG indoor signals if lock is active
        if isOutdoorTrackingLocked {
            // Outdoor lock is active - require strong signal to stop tracking
            let hasStrongSignal = await isStrongIndoorSignal(state)

            if !hasStrongSignal {
                if let lockTime = outdoorLockStartTime {
                    let duration = Date().timeIntervalSince(lockTime)
                    print("🔒 [BackgroundTaskManager] Outdoor lock active (\(Int(duration))s) - ignoring weak indoor signal (confidence: \(String(format: "%.2f", state.confidence)))")
                }
                return
            }

            // Strong signal detected - stop tracking and release lock
            print("🔓 [BackgroundTaskManager] Strong indoor signal detected - RELEASING outdoor lock and stopping UV tracking")
        } else {
            // Lock not active - use normal confidence threshold
            let minConfidence = 0.70  // Higher than old 0.60 threshold for stopping
            guard state.confidence >= minConfidence else {
                print("⚠️ [BackgroundTaskManager] Indoor detected but confidence too low (\(String(format: "%.2f", state.confidence)) < \(String(format: "%.2f", minConfidence)))")
                return
            }
        }

        if lastHandledMode == .inside {
            return
        }

        DetectionLogger.logUVTracking(
            action: "STOP",
            mode: .inside,
            confidence: state.confidence,
            reason: isOutdoorTrackingLocked ? "Strong indoor signal detected" : "Indoor detection confirmed"
        )

        await stopUVTrackingTimer()
        if let session = currentSession {
            try? await endUVSession(session)
        }

        // Release outdoor lock
        if isOutdoorTrackingLocked {
            isOutdoorTrackingLocked = false
            outdoorLockStartTime = nil
        }

        lastHandledMode = .inside
    }

    /// Check if current state represents a STRONG indoor signal (not just GPS drift)
    /// Strong signals are required to break the outdoor tracking lock
    /// Returns true only for definitive indoor evidence: polygon occupancy, floor detection, vehicle
    private func isStrongIndoorSignal(_ state: LocationManager.LocationState) async -> Bool {
        // STRONG SIGNAL 1: Currently inside a polygon with high confidence
        // Being physically inside a building polygon IS a strong signal - don't require sustained time
        let isInsidePolygon = await locationManager.isInsideAnyPolygon()
        let isStationary = (state.speed ?? 0) < 1.0  // Not actively walking

        if isInsidePolygon && state.mode == .inside && state.confidence >= 0.85 && isStationary {
            print("✅ Strong indoor: Inside polygon + high confidence (\(Int(state.confidence * 100))%) + stationary")
            return true
        }

        // STRONG SIGNAL 1B: Sustained polygon occupancy (>30s inside exact building boundary)
        // Fallback for cases where confidence is lower but duration is sustained
        let (isSustained, duration) = await locationManager.isInsidePolygonSustained()
        if isSustained {
            print("✅ Strong indoor: Inside polygon for \(Int(duration ?? 0))s")
            return true
        }

        // STRONG SIGNAL 2: Floor detection (only available in multi-story buildings)
        if await locationManager.hasRecentFloorDetection(within: 300) {
            print("✅ Strong indoor: Floor detected (multi-story building)")
            return true
        }

        // STRONG SIGNAL 3: Vehicle detection (high confidence, safety critical)
        if state.mode == .vehicle && state.confidence >= minConfidenceForVehicle {
            print("✅ Strong indoor: Vehicle detected (no UV through windshield)")
            return true
        }

        // STRONG SIGNAL 4: Stationary near building for extended period (3 min)
        // This catches cases where user entered building but polygon/floor detection missed it
        if state.mode == .inside && state.confidence >= 0.75 {
            if let duration = await locationManager.getCurrentPolygonDuration(), duration > 180 {
                print("✅ Strong indoor: Stationary near building >3min")
                return true
            }
        }

        // No strong signals detected
        return false
    }

    /// Check if vehicle is definitely parked (not just at red light or stop sign)
    /// Phase 1 Fix #2: Conservative parking detection to release vehicle lock
    /// Requires ALL of: 3+ minutes stationary, no automotive activity, very low speed
    private func isDefinitelyParked(state: LocationManager.LocationState) async -> Bool {
        guard let lockTime = vehicleLockStartTime else { return false }
        guard let lastVehicleTime = lastVehicleDetectionTime else { return false }

        let lockDuration = Date().timeIntervalSince(lockTime)
        let timeSinceVehicle = Date().timeIntervalSince(lastVehicleTime)

        // REQUIREMENT 1: At least 3 minutes since vehicle lock started
        guard lockDuration > 180 else {
            return false
        }

        // REQUIREMENT 2: No vehicle detection in last 2 minutes (no recent automotive activity)
        guard timeSinceVehicle > 120 else {
            return false
        }

        // REQUIREMENT 3: Current state shows stationary or indoor (not moving)
        guard state.mode == .inside || state.mode == .unknown else {
            // If classified as outdoor with movement, likely walking away from parked car
            // This is actually parking + exit, so release lock
            if state.mode == .outside {
                print("🚶 [BackgroundTaskManager] Outdoor movement detected after vehicle lock - likely exited parked vehicle")
                return true
            }
            return false
        }

        // REQUIREMENT 4: Low speed or stationary
        if let speed = state.speed, speed > 0.5 {
            // Still moving > 0.5 m/s (walking pace), not parked
            return false
        }

        // All requirements met - definitely parked
        print("🅿️ [BackgroundTaskManager] Parking detected: \(Int(lockDuration))s stationary, \(Int(timeSinceVehicle))s since last vehicle detection")
        return true
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

        lastOutsideDetectionTime = Date()
        try? await updateUVExposure()
        try? await updateVitaminD()
        // Note: Notifications are sent within updateUVExposure() and updateVitaminD()
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
                    // Note: Notifications are sent within updateUVExposure() and updateVitaminD()
                    // No need for legacy checkAndSendNotifications() call

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

            isUVTrackingActive = true
        }
    }
    
    /// Stop UV tracking timer
    private func stopUVTrackingTimer() async {
        await MainActor.run {
            // OPTIMIZATION: Skip if already stopped
            guard uvTrackingTimer != nil || currentBackgroundTask != .invalid else {
                return
            }

            print("🌙 [BackgroundTaskManager] Stopping UV tracking timer")

            uvTrackingTimer?.invalidate()
            uvTrackingTimer = nil

            if currentBackgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundTask)
                currentBackgroundTask = .invalid
            }

            isUVTrackingActive = false
        }
    }

    func startUVSession() async throws {
        guard let userId = await getCurrentUserId() else { return }

        // End any existing session
        if let existingSession = currentSession {
            try await endUVSession(existingSession)
        }

        // Create new session
        let sunscreenActive = isSunscreenActive()
        currentSession = UVSession(
            id: UUID(),
            userId: userId,
            date: Date(),
            startTime: Date(),
            endTime: nil,
            sessionSED: 0,
            sunscreenApplied: sunscreenActive,
            createdAt: Date()
        )

        if sunscreenActive {
            print("☀️ [BackgroundTaskManager] New session started with sunscreen protection active")
        }

        try await supabase.createUVSession(currentSession!)
    }

    func endUVSession(_ session: UVSession) async throws {
        var endedSession = session
        endedSession.endTime = Date()
        try await supabase.updateUVSession(endedSession)
        currentSession = nil

        // Clear tracking timestamps
        lastSEDUpdateTime = nil
        lastUVIndexFetchTime = nil

        // Clear published state for frontend
        await MainActor.run {
            currentSessionSED = 0.0
            currentSessionStartTime = nil
            currentExposureRatio = 0.0
        }

        // Clear notification state (prevent stale notifications from being sent)
        UserDefaults.standard.removeObject(forKey: "current_exposure_ratio")

        // CRITICAL: Sync Vitamin D to database BEFORE posting notification
        // This ensures the bar graph history will show the updated data
        await syncVitaminDToDatabase()

        // Notify frontend to reload history (includes vitamin D history)
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("UVSessionEnded"),
                object: nil
            )
        }

        print("🛑 [BackgroundTaskManager] UV session ended - ID: \(session.id), Duration: \(String(format: "%.0f", session.endTime?.timeIntervalSince(session.startTime) ?? 0))s, Total SED: \(String(format: "%.4f", session.sessionSED))")
    }

    // MARK: - Vitamin D Database Sync

    /// Syncs current Vitamin D data to database
    /// Called at: session end, app backgrounding, midnight
    func syncVitaminDToDatabase() async {
        guard let vitaminDData = dailyVitaminD else {
            print("💊 [BackgroundTaskManager] No Vitamin D data to sync")
            return
        }

        do {
            try await supabase.updateVitaminDData(vitaminDData)
            print("💊 [BackgroundTaskManager] Vitamin D synced to database: \(String(format: "%.1f", vitaminDData.totalIU)) IU")
        } catch {
            print("❌ [BackgroundTaskManager] Failed to sync Vitamin D to database: \(error)")
        }
    }

    // Sunscreen application removed - not required for notification system

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

    /// Check UV exposure and send notifications at 75% (warning) and 100% (danger) thresholds
    private func checkAndSendUVNotifications(exposureRatio: Double, profile: Profile) async {
        let now = Date()
        let timeSinceLastNotification = now.timeIntervalSince(lastNotificationTime)
        let cooldownPeriod: TimeInterval = 600 // 10 minutes between notifications

        // Warning at 90% MED (changed from 75% to avoid spam)
        let warningThreshold = 0.90
        let hasWarnedToday = UserDefaults.standard.bool(forKey: "uv_warned_90_\(dateKey())")

        if exposureRatio >= warningThreshold && exposureRatio < 1.0 && !hasWarnedToday {
            if timeSinceLastNotification > cooldownPeriod {
                await notificationManager.sendUVWarningNotification(exposureRatio: exposureRatio)
                UserDefaults.standard.set(true, forKey: "uv_warned_90_\(dateKey())")
                lastNotificationTime = now
                print("⚠️ [BackgroundTaskManager] UV warning notification sent (90% threshold)")
            }
        }

        // Danger at 100% MED
        let hasDangerNotifiedToday = UserDefaults.standard.bool(forKey: "uv_danger_\(dateKey())")

        if exposureRatio >= 1.0 && !hasDangerNotifiedToday {
            // Bypass cooldown for danger notifications (critical safety alert)
            await notificationManager.sendUVDangerNotification(exposureRatio: exposureRatio)
            UserDefaults.standard.set(true, forKey: "uv_danger_\(dateKey())")
            lastNotificationTime = now
            print("🚨 [BackgroundTaskManager] UV DANGER notification sent (100% threshold)")
        }
    }

    /// Check Vitamin D levels and send notification when daily target is reached
    private func checkAndSendVitaminDNotification(vitaminDData: VitaminDData, profile: Profile) async {
        let targetIU = vitaminDData.targetIU
        let hasNotifiedToday = UserDefaults.standard.bool(forKey: "vitamin_d_notified_\(dateKey())")

        // Check if we just reached the target
        if vitaminDData.totalIU >= targetIU && !hasNotifiedToday {
            await notificationManager.sendVitaminDTargetReachedNotification()
            UserDefaults.standard.set(true, forKey: "vitamin_d_notified_\(dateKey())")
            print("🎉 [BackgroundTaskManager] Vitamin D target reached notification sent (\(Int(vitaminDData.totalIU))/\(Int(targetIU)) IU)")
        }
    }

    /// Legacy notification check - kept for compatibility
    private func checkAndSendNotifications() async {
        guard let exposureRatio = UserDefaults.standard.object(forKey: "current_exposure_ratio") as? Double else {
            return
        }

        // This is now handled in checkAndSendUVNotifications() called from updateUVExposure()
        // Keeping this function for backward compatibility with existing code paths
        print("⚠️ [BackgroundTaskManager] Legacy checkAndSendNotifications called - consider using new methods")
    }

    // Daily summary notification removed - not required

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
        // Return cached value from location manager
        return await locationManager.uvIndex
    }

    /// Fetch UV index with automatic refresh if cache is stale
    private func fetchCurrentUVIndexWithRefresh() async -> Double {
        let now = Date()

        // Check if we need to refresh (>15 minutes old or never fetched)
        let shouldRefresh: Bool
        if let lastFetch = lastUVIndexFetchTime {
            let timeSinceFetch = now.timeIntervalSince(lastFetch)
            shouldRefresh = timeSinceFetch > AppConfig.uvIndexCacheDuration
        } else {
            shouldRefresh = true
        }

        if shouldRefresh {
            // Fetch fresh UV index from weather service
            if let location = await locationManager.currentLocation {
                do {
                    let freshUVIndex = try await WeatherService.shared.getCurrentUVIndex(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    lastUVIndexFetchTime = now
                    cachedUVIndex = freshUVIndex  // Store for subsequent calls
                    print("🌤️ UV index refreshed: \(String(format: "%.1f", freshUVIndex))")
                    return freshUVIndex
                } catch {
                    print("⚠️ [BackgroundTaskManager] Failed to refresh UV index: \(error)")
                }
            }
        }

        // Return cached value (stored from last successful fetch)
        // Fall back to locationManager if we never fetched
        if cachedUVIndex > 0 {
            return cachedUVIndex
        }
        return await locationManager.uvIndex
    }

    private func resetDailyCounters() async {
        dailyVitaminD = nil
        currentSession = nil
        lastSEDUpdateTime = nil
        lastUVIndexFetchTime = nil
        lastKnownDate = Date()

        // Clear published state
        await MainActor.run {
            currentSessionSED = 0.0
            currentSessionStartTime = nil
            currentExposureRatio = 0.0
            currentVitaminD = 0.0
            vitaminDProgress = 0.0
        }

        // Notify frontend of day change for history refresh
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("DayChanged"),
                object: nil
            )
        }

        print("🌅 [BackgroundTaskManager] Daily counters reset - new day started")
    }

    // MARK: - Day Change Detection

    /// Checks if the day has changed since last check and handles midnight reset
    /// Called from: app foreground, location updates, vitamin D updates
    func checkForDayChange() async {
        let calendar = Calendar.current
        let now = Date()

        // Initialize lastKnownDate if nil
        guard let lastDate = lastKnownDate else {
            lastKnownDate = now
            return
        }

        // Check if we've crossed midnight
        if !calendar.isDate(lastDate, inSameDayAs: now) {
            print("🌅 [BackgroundTaskManager] Day change detected - syncing and resetting")

            // Sync yesterday's vitamin D data to database before reset
            await syncVitaminDToDatabase()

            // Update streaks for yesterday
            do {
                try await updateStreaks()
            } catch {
                print("❌ [BackgroundTaskManager] Failed to update streaks on day change: \(error)")
            }

            // Reset counters for new day
            await resetDailyCounters()
        }
    }

    private func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Sunscreen State Helpers

    /// Check if sunscreen is currently active (synced with ViewModel via UserDefaults)
    private func isSunscreenActive() -> Bool {
        let isActive = UserDefaults.standard.bool(forKey: sunscreenStateKey)

        guard isActive, let appliedTimeInterval = UserDefaults.standard.object(forKey: sunscreenTimeKey) as? TimeInterval else {
            return false
        }

        let appliedTime = Date(timeIntervalSince1970: appliedTimeInterval)
        let elapsed = Date().timeIntervalSince(appliedTime)

        // Check if still within protection duration
        if elapsed < AppConfig.sunscreenProtectionDuration {
            return true
        } else {
            // Expired - clear state
            clearExpiredSunscreen()
            return false
        }
    }

    /// Get time when sunscreen was applied (if active)
    private func getSunscreenAppliedTime() -> Date? {
        guard isSunscreenActive(),
              let appliedTimeInterval = UserDefaults.standard.object(forKey: sunscreenTimeKey) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: appliedTimeInterval)
    }

    /// Clear expired sunscreen state
    private func clearExpiredSunscreen() {
        UserDefaults.standard.removeObject(forKey: sunscreenStateKey)
        UserDefaults.standard.removeObject(forKey: sunscreenTimeKey)
        print("⏰ [BackgroundTaskManager] Sunscreen expired - cleared state")
    }
}
