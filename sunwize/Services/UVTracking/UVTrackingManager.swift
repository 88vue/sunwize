import Foundation
import CoreLocation

// MARK: - UV Tracking Manager

/// Main orchestrator for UV exposure tracking
/// Manages outdoor/vehicle tracking locks and UV session lifecycle
@MainActor
class UVTrackingManager: ObservableObject {
    static let shared = UVTrackingManager()

    // MARK: - Services

    private let sessionStore = UVSessionStore.shared
    private let notificationService = UVNotificationService.shared
    private let supabase = SupabaseManager.shared
    private let weatherService = WeatherService.shared

    // MARK: - Published State

    @Published private(set) var isUVTrackingActive: Bool = false

    // Forward from session store
    var currentSessionSED: Double { sessionStore.currentSessionSED }
    var currentSessionStartTime: Date? { sessionStore.currentSessionStartTime }
    var currentExposureRatio: Double { sessionStore.currentExposureRatio }
    var currentVitaminD: Double { sessionStore.currentVitaminD }
    var vitaminDProgress: Double { sessionStore.vitaminDProgress }

    // MARK: - Tracking Locks

    /// Outdoor tracking lock - maintains UV tracking while walking past buildings
    private(set) var isOutdoorTrackingLocked: Bool = false
    private var outdoorLockStartTime: Date?
    private var lastOutsideDetectionTime: Date?
    private var unknownHoldStartTime: Date?

    /// Vehicle tracking lock - maintains vehicle state during stop-and-go driving
    private(set) var isVehicleTrackingLocked: Bool = false
    private var vehicleLockStartTime: Date?
    private var lastVehicleDetectionTime: Date?

    // MARK: - Confidence Thresholds

    private let minConfidenceForOutdoorStart: Double = 0.85
    private let minConfidenceForVehicle: Double = 0.85
    private let minConfidenceForIndoorStop: Double = 0.70

    // MARK: - UV Tracking Timer

    private var uvTrackingTimer: Timer?
    private var cachedUVIndex: Double = 0.0
    private var lastUVIndexFetchTime: Date?

    // Background task service for timer renewal
    private let backgroundTaskService = BackgroundTaskService.shared

    // MARK: - Mode Tracking

    private var lastHandledMode: LocationMode = .unknown
    private var vehicleDetectionSampleCount = 0

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Lock State

    var outdoorLockActive: Bool { isOutdoorTrackingLocked }
    var vehicleLockActive: Bool { isVehicleTrackingLocked }

    // MARK: - Outside Detection Handler

    /// Called when outdoor mode is detected
    func handleOutsideDetection(
        location: CLLocation,
        state: LegacyLocationState,
        isManualOverrideActive: Bool,
        nearestBuildingDistance: Double?,
        isInsidePolygon: Bool,
        hasRecentPolygonExit: Bool,
        hasExcellentGPS: Bool
    ) async {
        // Check manual override
        if isManualOverrideActive {
            await handleManualOverrideActive()
            return
        }

        guard state.mode == .outside else {
            await handleInsideDetection(state: state, nearestBuildingDistance: nearestBuildingDistance, isInsidePolygon: isInsidePolygon)
            return
        }

        // Check vehicle lock - blocks outdoor classification
        if isVehicleTrackingLocked {
            let lockDuration = vehicleLockStartTime.map { Date().timeIntervalSince($0) } ?? 0
            print("[UVTrackingManager] Vehicle lock active (\(Int(lockDuration))s) - blocking outdoor")
            lastHandledMode = .vehicle
            return
        }

        // Check daytime
        guard isDaytime() else {
            await handleInsideDetection(state: state, nearestBuildingDistance: nearestBuildingDistance, isInsidePolygon: isInsidePolygon)
            return
        }

        // TIER 2: Already locked - maintain outdoor state
        if isOutdoorTrackingLocked {
            if let lockTime = outdoorLockStartTime {
                let duration = Date().timeIntervalSince(lockTime)
                print("[UVTrackingManager] Outdoor lock active (\(Int(duration))s) - maintaining UV tracking")
            }

            lastHandledMode = .outside
            lastOutsideDetectionTime = Date()
            unknownHoldStartTime = nil
            try? await updateUVExposure()
            return
        }

        // TIER 1: Starting UV tracking - conservative validation
        guard state.confidence >= minConfidenceForOutdoorStart else {
            print("[UVTrackingManager] Outside detected but confidence too low (\(String(format: "%.2f", state.confidence)))")
            return
        }

        // Distance safety check
        if let distance = nearestBuildingDistance, distance < 25 {
            let hasWalking = state.activity == .walking || state.activity == .running
            let hasGoodGPS = (state.accuracy ?? 100) < 30

            if hasRecentPolygonExit {
                print("[UVTrackingManager] Close to building but polygon exit - outdoor allowed")
            } else if hasWalking && hasGoodGPS && state.confidence >= 0.85 {
                print("[UVTrackingManager] Close to building but walking + good GPS - sidewalk detected")
            } else {
                print("[UVTrackingManager] Too close to building without clear outdoor evidence - blocking")
                return
            }
        }

        // Activate outdoor lock and start tracking
        isOutdoorTrackingLocked = true
        outdoorLockStartTime = Date()
        lastOutsideDetectionTime = Date()
        unknownHoldStartTime = nil
        print("[UVTrackingManager] OUTDOOR LOCK ACTIVATED")

        if uvTrackingTimer == nil {
            await startUVTrackingTimer()
        }

        lastHandledMode = .outside
        try? await updateUVExposure()
    }

    // MARK: - Inside Detection Handler

    /// Called when indoor/vehicle/unknown mode is detected
    func handleInsideDetection(
        state: LegacyLocationState,
        nearestBuildingDistance: Double?,
        isInsidePolygon: Bool
    ) async {
        // Handle unknown mode with debounce
        if state.mode == .unknown {
            await handleUnknownMode(state: state)
            return
        }

        // Handle vehicle mode
        if state.mode == .vehicle {
            await handleVehicleMode(state: state)
            return
        }

        // Reset vehicle counter
        vehicleDetectionSampleCount = 0

        // Check vehicle lock maintenance
        if isVehicleTrackingLocked {
            let parked = await isDefinitelyParked(state: state)
            if parked {
                releaseVehicleLock(reason: "parking detected")
            } else {
                print("[UVTrackingManager] Vehicle lock active - ignoring indoor classification")
                lastHandledMode = .vehicle
                return
            }
        }

        // TIER 3: Check if strong signal needed to break outdoor lock
        if isOutdoorTrackingLocked {
            let hasStrongSignal = await isStrongIndoorSignal(
                state: state,
                isInsidePolygon: isInsidePolygon,
                nearestBuildingDistance: nearestBuildingDistance
            )

            if !hasStrongSignal {
                if let lockTime = outdoorLockStartTime {
                    let duration = Date().timeIntervalSince(lockTime)
                    print("[UVTrackingManager] Outdoor lock active (\(Int(duration))s) - ignoring weak indoor signal")
                }
                return
            }

            print("[UVTrackingManager] Strong indoor signal - releasing outdoor lock")
        } else {
            guard state.confidence >= minConfidenceForIndoorStop else {
                return
            }
        }

        // Stop UV tracking
        await stopUVTracking(reason: "indoor detection")
        lastHandledMode = .inside
    }

    // MARK: - Unknown Mode Handling

    private func handleUnknownMode(state: LegacyLocationState) async {
        let now = Date()
        let recentOutside = lastOutsideDetectionTime.map { now.timeIntervalSince($0) < AppConfig.unknownHoldDebounce } ?? false

        if isOutdoorTrackingLocked {
            if recentOutside {
                lastHandledMode = .unknown
                return
            }

            if unknownHoldStartTime == nil {
                unknownHoldStartTime = now
                stopUVTrackingTimer()
                lastHandledMode = .unknown
                return
            }

            let elapsed = now.timeIntervalSince(unknownHoldStartTime!)
            if elapsed < AppConfig.unknownHoldDebounce {
                lastHandledMode = .unknown
                return
            }

            await stopUVTracking(reason: "unknown mode timeout")
        }

        stopUVTrackingTimer()
        releaseOutdoorLock()
        unknownHoldStartTime = nil
        lastHandledMode = .unknown
        vehicleDetectionSampleCount = 0
    }

    // MARK: - Vehicle Mode Handling

    private func handleVehicleMode(state: LegacyLocationState) async {
        guard state.confidence >= minConfidenceForVehicle else {
            vehicleDetectionSampleCount = 0
            return
        }

        lastVehicleDetectionTime = Date()

        if lastHandledMode == .vehicle {
            vehicleDetectionSampleCount += 1
            return
        }

        // Activate vehicle lock
        if !isVehicleTrackingLocked {
            releaseOutdoorLock()
            isVehicleTrackingLocked = true
            vehicleLockStartTime = Date()
            print("[UVTrackingManager] VEHICLE LOCK ACTIVATED")
        }

        await stopUVTracking(reason: "vehicle detection")
        lastHandledMode = .vehicle
        vehicleDetectionSampleCount = 1
    }

    // MARK: - Manual Override

    private func handleManualOverrideActive() async {
        print("[UVTrackingManager] Manual override active - treating as inside")

        if isUVTrackingActive {
            await stopUVTracking(reason: "manual override")
        }

        releaseOutdoorLock()
        lastHandledMode = .inside
    }

    // MARK: - Strong Indoor Signal

    private func isStrongIndoorSignal(
        state: LegacyLocationState,
        isInsidePolygon: Bool,
        nearestBuildingDistance: Double?
    ) async -> Bool {
        // Floor detection = DEFINITIVE indoor (multi-story buildings, malls, offices)
        if LocationManager.shared.hasRecentFloorDetection(within: 60) {
            print("[UVTrackingManager] Floor detection - strong indoor signal")
            return true
        }

        // Sustained polygon occupancy (>30s)
        if isInsidePolygon {
            // Would need to check duration from history
            return true
        }

        // Very close to building + stationary (>3 min)
        if let distance = nearestBuildingDistance,
           distance < 10,
           state.activity == .stationary {
            return true
        }

        // High confidence inside detection
        if state.mode == .inside && state.confidence >= 0.90 {
            return true
        }

        return false
    }

    // MARK: - Parking Detection

    private func isDefinitelyParked(state: LegacyLocationState) async -> Bool {
        guard let lockTime = vehicleLockStartTime else { return false }

        let timeSinceLock = Date().timeIntervalSince(lockTime)
        let timeSinceVehicle = lastVehicleDetectionTime.map { Date().timeIntervalSince($0) } ?? Double.infinity

        // If currently outdoor with movement, likely walking away from parked car
        if state.mode == .outside && (state.activity == .walking || state.activity == .running) {
            print("[UVTrackingManager] Outdoor movement detected - likely exited parked vehicle")
            return true
        }

        // Parking detection: 3+ minutes since lock, 2+ minutes without vehicle detection, slow speed
        let speed = state.speed ?? 0
        if timeSinceLock > 180 && timeSinceVehicle > 120 && speed < 0.5 {
            print("[UVTrackingManager] Parking detected: \(Int(timeSinceLock))s since lock, \(Int(timeSinceVehicle))s since vehicle")
            return true
        }

        return false
    }

    // MARK: - Lock Management

    private func releaseOutdoorLock() {
        if isOutdoorTrackingLocked {
            isOutdoorTrackingLocked = false
            outdoorLockStartTime = nil
            print("[UVTrackingManager] Outdoor lock RELEASED")
        }
    }

    private func releaseVehicleLock(reason: String) {
        if isVehicleTrackingLocked {
            let duration = vehicleLockStartTime.map { Date().timeIntervalSince($0) } ?? 0
            isVehicleTrackingLocked = false
            vehicleLockStartTime = nil
            lastVehicleDetectionTime = nil
            print("[UVTrackingManager] Vehicle lock RELEASED (\(reason) after \(Int(duration))s)")
        }
    }

    // MARK: - UV Tracking Timer

    private func startUVTrackingTimer() async {
        guard uvTrackingTimer == nil else { return }

        isUVTrackingActive = true

        // Get UV index for interval calculation
        let uvIndex = await fetchCurrentUVIndex()
        let interval = UVExposureCalculator.getTrackingInterval(for: uvIndex)

        uvTrackingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                // Begin background task for timer execution
                let taskID = self.backgroundTaskService.beginBackgroundTask(name: "UVTrackingUpdate")

                try? await self.updateUVExposure()

                // End background task when done
                if taskID != .invalid {
                    self.backgroundTaskService.endBackgroundTask()
                }
            }
        }

        print("[UVTrackingManager] UV tracking timer started (interval: \(Int(interval))s)")
    }

    private func stopUVTrackingTimer() {
        uvTrackingTimer?.invalidate()
        uvTrackingTimer = nil
    }

    private func stopUVTracking(reason: String) async {
        stopUVTrackingTimer()

        if sessionStore.isSessionActive {
            try? await sessionStore.endSession()
        }

        releaseOutdoorLock()
        isUVTrackingActive = false

        print("[UVTrackingManager] UV tracking stopped: \(reason)")
    }

    // MARK: - UV Exposure Update

    private func updateUVExposure() async throws {
        guard isUVTrackingActive && isOutdoorTrackingLocked else { return }

        guard let userId = await getCurrentUserId(),
              let profile = try? await supabase.getProfile(userId: userId) else {
            return
        }

        // Ensure session exists
        if !sessionStore.isSessionActive {
            try await sessionStore.startSession(userId: userId)
        }

        // Get UV index
        let uvIndex = await fetchCurrentUVIndex()

        // Calculate SED increment
        let interval = sessionStore.getTimeSinceLastUpdate()
        let sedIncrement = UVExposureCalculator.calculateSED(uvIndex: uvIndex, exposureSeconds: interval)

        // Update session
        try await sessionStore.updateSession(sedIncrement: sedIncrement, userMED: Double(profile.med))

        // Check notifications
        await notificationService.checkAndSendUVNotifications(
            exposureRatio: sessionStore.currentExposureRatio,
            profile: profile
        )

        // Update Vitamin D
        try await updateVitaminD(userId: userId, profile: profile, uvIndex: uvIndex)
    }

    private func updateVitaminD(userId: UUID, profile: Profile, uvIndex: Double) async throws {
        guard let settings = try? await supabase.getFeatureSettings(userId: userId),
              settings.vitaminDTrackingEnabled else {
            return
        }

        try await sessionStore.loadVitaminD(userId: userId)

        guard let vitaminD = sessionStore.dailyVitaminD else { return }

        let interval = min(60, sessionStore.getTimeSinceLastUpdate())
        let latitude = LocationService.shared.currentLocation?.coordinate.latitude ?? 0

        let increment = VitaminDCalculations.calculateVitaminD(
            uvIndex: uvIndex,
            exposureSeconds: interval,
            bodyExposureFactor: vitaminD.bodyExposureFactor,
            skinType: profile.skinType,
            latitude: latitude,
            date: Date()
        )

        try await sessionStore.updateVitaminD(increment: increment)

        await notificationService.checkAndSendVitaminDNotification(
            vitaminDData: vitaminD,
            profile: profile
        )
    }

    // MARK: - UV Index

    private func fetchCurrentUVIndex() async -> Double {
        // Use cache if fresh
        if let lastFetch = lastUVIndexFetchTime,
           Date().timeIntervalSince(lastFetch) < 300 {
            return cachedUVIndex
        }

        guard let location = LocationService.shared.currentLocation else {
            return cachedUVIndex
        }

        do {
            let uvIndex = try await weatherService.getCurrentUVIndex(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            cachedUVIndex = uvIndex
            lastUVIndexFetchTime = Date()
            return uvIndex
        } catch {
            print("[UVTrackingManager] Failed to fetch UV index: \(error)")
            return cachedUVIndex
        }
    }

    // MARK: - Helpers

    private func isDaytime() -> Bool {
        return DaytimeService.shared.isDaytime
    }

    private func getCurrentUserId() async -> UUID? {
        // Get from stored credentials
        guard let userIdString = UserDefaults.standard.string(forKey: "user_id"),
              let userId = UUID(uuidString: userIdString) else {
            return nil
        }
        return userId
    }

    // MARK: - Daily Reset

    /// Reset daily state (called at midnight)
    func resetDailyState() async {
        await sessionStore.resetDailyCounters()
        notificationService.resetDailyState()
        print("[UVTrackingManager] Daily state reset")
    }
}
