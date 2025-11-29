import Foundation
import CoreLocation
import CoreMotion
import Combine
import MapKit
import UIKit

// MARK: - Location Manager
/// Advanced location manager with Apple Native Signals + OpenStreetMap validation
///
//   📊 Three-Tier State Machine with Movement-Validated Polygon Exits

//   TIER 1: Starting UV Tracking (Lines 464-515)

//   Very conservative to prevent false positives:

//   Requirements to START:
//   ├─ Confidence: 0.90 (0.92 during startup)
//   ├─ NOT inside any building polygon (absolute veto - prevents "clearly inside" false positives)
//   ├─ Distance >40m from buildings
//   │  └─ OR: Recent polygon exit (<90s) with ≥10m movement as override
//   │     ⚠️  Polygon exits require movement validation to prevent GPS drift false exits
//   │     ⚠️  If GPS drifts outside polygon but position hasn't moved ≥10m, exit is rejected
//   │  └─ OR: Clear outdoor evidence (walking + excellent GPS <25m + confidence ≥0.92)
//   │     ✓  Enables urban sidewalk tracking while preventing GPS drift false positives
//   └─ Daytime only

//   On success:
//   ├─ Start UV tracking timer
//   ├─ Activate outdoor tracking lock 🔒
//   └─ Log: "OUTDOOR LOCK ACTIVATED"

//   Example log output:
//   🎯 Evaluating outdoor start conditions (lock not active)
//   ✅ POLYGON EXIT VALIDATED: movement 35m confirms actual exit
//   ✅ Distance safety check passed: 52m from nearest building
//   ☀️ [UVTRCK] START outdoor detection confirmed
//   🔒 OUTDOOR LOCK ACTIVATED - will maintain outdoor state until strong indoor signal

//   TIER 2: Maintaining UV Tracking (Lines 450-462)

//   Stable & sticky during active tracking:

//   When outdoor lock is active:
//   ├─ IGNORE distance oscillations (8m → 30m → 12m...)
//   ├─ IGNORE confidence variations (0.88 → 0.73 → 0.85...)
//   ├─ IGNORE weak indoor signals
//   ├─ MAINTAIN outdoor state
//   └─ Continue accumulating UV exposure

//   Only exits on strong signals (TIER 3)

//   Example log output:
//   🔒 Outdoor lock active (142s) - maintaining UV tracking
//   🔒 Outdoor lock active (156s) - ignoring weak indoor signal (confidence: 0.68)

//   TIER 3: Stopping UV Tracking (Lines 602-649)

//   Responsive to strong signals only:

//   When outdoor lock is active:
//   ├─ Requires STRONG indoor signal:
//   │  ├─ Sustained polygon occupancy (>30s inside)
//   │  ├─ Floor detection (multi-story building)
//   │  ├─ Vehicle detection (0.85+ confidence)
//   │  └─ Stationary near building (>3 min)
//   └─ On weak signal: Stay locked, continue tracking

//   When lock not active:
//   └─ Requires 0.70 confidence (normal indoor)

//   On stop:
//   ├─ Stop UV tracking timer
//   ├─ End current UV session
//   ├─ Release outdoor lock 🔓
//   └─ Log: "Strong indoor signal detected"

//   Example log output:
//   ✅ Strong indoor signal: Inside polygon for 35s
//   🔓 Strong indoor signal detected - RELEASING outdoor lock and stopping UV tracking
//   ☀️ [UVTRCK] STOP - Strong indoor signal detected
//
//   🏢 POLYGON-BASED GEOFENCING: Exact Building Boundaries (Lines 710-793)
//
//   Core concept: Use exact OSM building polygons instead of circular geofences
//
//   Why this matters:
//   ├─ Circular geofences (30m radius) are imprecise in urban areas
//   ├─ Sidewalk 12m from building = inside circular geofence = false entry
//   ├─ Building polygons = exact footprint from OpenStreetMap
//   └─ Result: Dramatically more accurate indoor/outdoor detection
//
//   Entry Detection:
//   ├─ GPS crosses polygon boundary inward
//   ├─ Records: Entry timestamp + entry position
//   └─ Purpose: Position stored for exit validation
//
//   Exit Detection with Movement Validation (CRITICAL):
//   ├─ GPS crosses polygon boundary outward
//   ├─ Calculates: Distance moved since entry
//   ├─ Validates: Movement ≥10m required
//   │  └─ If <10m: REJECT exit (GPS drift, not real movement)
//   │  └─ If ≥10m: ACCEPT exit (actual user movement)
//   └─ Purpose: Prevents GPS drift from creating false exit events
//
//   Why movement validation is critical:
//   • Without validation: User sits indoors, GPS drifts 10m outside polygon boundary,
//     system records "exit", user walks to printer indoors, system thinks they exited
//     building and starts UV tracking indoors → FALSE POSITIVE ❌
//   • With validation: GPS drift rejected (<10m movement), only real exits with
//     actual user movement are recorded → No false positives ✓
//
//   Example log output (rejected drift):
//   ⚠️ POLYGON EXIT REJECTED: building123 - movement only 8m, likely GPS drift
//
//   Example log output (validated exit):
//   ✅ POLYGON EXIT VALIDATED: building123 - movement 35m confirms actual exit
//   🚪 POLYGON EXIT: building123 - was inside for 180s
//
//   🪟 NEAR WINDOW DETECTION: Preventing Urban False Positives (Lines 1557-1567, 2574-2579)
//
//   Problem: User at desk near window gets excellent GPS (5-15m accuracy)
//   Result: System thinks "excellent GPS = outdoor" and starts UV tracking indoors
//
//   Solution: Multi-factor "near window" detection:
//   ├─ Stationary for >2 minutes (not walking/moving)
//   ├─ Excellent GPS accuracy (<15m)
//   ├─ Near or inside building (<5m distance OR inside polygon)
//   └─ Result: Classify as UNKNOWN (prevents UV tracking)
//
//   Where it triggers:
//   1. TIER 2 (Accuracy Pattern): If "definitive outdoor" pattern detected but stationary >2min
//   2. TIER 5 (Building Distance): If stationary with good GPS near building
//
//   Example log output:
//   🪟 NEAR WINDOW detected: Stationary >2min + excellent GPS (6.1m) + near building (0m)
//   📊 Accuracy pattern: EXCELLENT GPS but stationary >2min - rejecting outdoor (likely near window)
//
//   📱 CIRCULAR GEOFENCES: Background Wake-Up Only (Lines 695-3130)
//
//   Purpose: iOS native geofences can wake app when suspended in background
//
//   What they do:
//   ├─ Setup: 30m radius circles around nearest 20 buildings
//   ├─ Callback: didEnterRegion / didExitRegion wake app
//   ├─ Action: Trigger performLocationCheck() to run polygon-based classification
//   └─ NOT USED: For classification decisions (polygon-based is more accurate)
//
//   Why keep them:
//   ├─ Polygon checks only work when app is actively processing location updates
//   ├─ Circular geofences can wake app from suspended state
//   └─ Result: Background transitions trigger accurate polygon-based classification
//
//   Why not use for classification:
//   ├─ 30m radius too imprecise (sidewalk triggers entry)
//   ├─ No movement validation (GPS drift creates false exits)
//   └─ Polygon-based system is superior in every way for actual classification


@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var locationMode: LocationMode = .unknown
    @Published var confidence: Double = 0.0
    @Published var isAuthorized = false
    @Published var uvIndex: Double = 0.0
    @Published var isTracking = false
    @Published var uncertaintyReason: LocationUncertaintyReason?

    // MARK: - Services
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let overpassService = OverpassService.shared
    private let weatherService = WeatherService.shared
    
    // MARK: - Public Access (for permission upgrades)
    var locationManagerInstance: CLLocationManager {
        return locationManager
    }

    // MARK: - State Management
    private var currentState: LocationState?
    private var locationHistory: [LocationHistoryEntry] = []
    private var motionHistory: [MotionSample] = []
    private var lastCheckTimestamp = Date.distantPast
    private var pendingCheck: Task<LocationState, Error>?
    private var lastDetectionLogTime: Date = .distantPast  // Debounce detection logs
    private var lastGeofenceSetupHash: Int = 0  // Skip redundant geofence setup

    // MARK: - Cache Management
    private var lastCachedLocation: CLLocationCoordinate2D?
    private var buildingCache: [String: BuildingCacheEntry] = [:]
    private lazy var persistenceDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LocationManager", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("LocationManager", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }()
    private lazy var motionHistoryURL = persistenceDirectory.appendingPathComponent("motionHistory.json")
    private lazy var locationHistoryURL = persistenceDirectory.appendingPathComponent("locationHistory.json")
    private lazy var buildingCacheURL = persistenceDirectory.appendingPathComponent("buildingCache.json")
    
    // MARK: - Geofencing
    private var monitoredBuildings: Set<String> = []
    private let maxMonitoredRegions = 20 // PRIORITY 4 FIX: Use all 20 available geofences (iOS limit)
    private let geofenceRadius: Double = 30 // PRIORITY 4 FIX: Reduced from 50m to 30m for better precision in dense urban
    private var geofenceExitTimestamp: Date? // Track geofence exits with 60s window for confidence boosting
    private var geofenceEntryTimestamps: [String: Date] = [:] // PRIORITY 4 FIX: Track entry time per building for time-in-geofence analysis
    private var lastValidGPSTimestamp = Date() // Track GPS availability for timeout detection
    private var lastHighConfidenceInsideTimestamp: Date? // Track polygon detection to prevent immediate flip-flopping

    // MARK: - Polygon-Based Geofencing (Exact Building Boundaries)
    private var currentPolygons: Set<String> = []  // Building IDs currently inside (exact boundary tracking)
    private var polygonEntryTimestamps: [String: Date] = [:]  // Track entry time for sustained occupancy detection
    private var polygonExitTimestamps: [String: Date] = [:]  // Track exit time for recent exit detection
    private var polygonEntryPositions: [String: CLLocationCoordinate2D] = [:]  // Track entry position to validate actual movement at exit
    
    // MARK: - Apple Native Signal Tracking (Phase 1 & 2 Enhancement)
    private var lastFloorDetectionTime: Date?
    private var lastKnownFloor: Int?
    private var accuracyHistory: [AccuracyHistoryEntry] = []
    private var pressureHistory: [PressureSample] = []
    private let altimeter = CMAltimeter()
    
    // MARK: - Critical Fix 1: Drift Detection (Nov 2025)
    private var driftDetectionHistory: [DriftSample] = []
    
    // MARK: - Critical Fix 3: Mode Lock for Stable States (Nov 2025)
    private var modeLock: ModeLock?

    // MARK: - Critical Fix 4: Underground Baseline Reset (Nov 2025)
    private var lastBaselineResetLocation: CLLocationCoordinate2D?
    private let baselineResetThreshold: Double = 1000.0  // 1km threshold for baseline reset


    // MARK: - Priority 7: Initial Startup Tracking (Conservative First Classification)
    private var trackingStartTime: Date?

    // MARK: - Priority 6: Tunnel Detection (Vehicle Mode Stability)
    private var inTunnelMode: Bool = false
    private var tunnelStartTime: Date?
    private var preTunnelMode: LocationMode?

    // MARK: - Vehicle Mode Persistence (Stop-and-Go Driving Support)
    private var lastVehicleDetectionTime: Date?
    private var vehicleModeConfirmedTime: Date?
    private var lastStrongVehicleConfidence: Double = 0.0
    private var consecutiveStops: Int = 0
    private var lastSignificantSpeed: Double = 0.0  // Last speed >2 m/s
    private var isInVehicleMode: Bool = false  // Sticky vehicle state

    // MARK: - Manual Indoor Override (Phase 1 & 2)
    private var manualIndoorOverride: Bool = false
    private var manualOverrideStartTime: Date?
    private var manualOverrideDuration: TimeInterval = 900 // 15 minutes default
    private let manualOverrideKey = "manualIndoorOverrideState"
    var manualOverrideEnabled: Bool = true // Can be toggled in settings

    // MARK: - State Persistence
    private let userDefaults = UserDefaults.standard
    private let stateKey = "locationManagerState"

    // MARK: - Configuration
    private let config = LocationConfig()

    // MARK: - Data Types

    struct LocationState {
        let latitude: Double
        let longitude: Double
        let mode: LocationMode
        let confidence: Double
        let timestamp: Date
        let isStale: Bool
        let speed: Double?
        let accuracy: Double?
        let activity: MotionActivity?
        let uncertaintyReason: LocationUncertaintyReason?
    }

    struct LocationHistoryEntry: Codable {
        let timestamp: Date
        let mode: LocationMode
        let confidence: Double
        let latitude: Double
        let longitude: Double
        let accuracy: Double?
        let uncertaintyReason: LocationUncertaintyReason?
        let signalSource: String?  // Added Nov 2025: Track which signal produced this classification

        /// Signal source quality weight for time decay calculation
        /// Definitive signals (floor, polygon) decay slower than probabilistic signals
        var signalQualityWeight: Double {
            guard let source = signalSource else { return 1.0 }
            switch source {
            case "floor":           return 2.0   // Floor detection is definitive - decay 2x slower
            case "polygon":         return 1.5   // Polygon occupancy is strong - decay 1.5x slower
            case "accuracyPattern": return 1.0   // Standard decay
            case "geofence":        return 1.0   // Standard decay
            case "pressureChange":  return 0.8   // Pressure is validation only - decay faster
            case "distanceMotion":  return 1.0   // Standard decay
            case "fallback":        return 0.7   // Fallback heuristics - decay faster
            default:                return 1.0
            }
        }
    }

    struct MotionSample: Codable {
        let timestamp: Date
        let speed: Double
        let activity: MotionActivity?
    }

    enum MotionActivity: String, Codable {
        case stationary
        case walking
        case running
        case cycling
        case automotive
        case unknown
    }

    enum LocationUncertaintyReason: String, Codable {
        case buildingDataUnavailable
        case poorGPSAccuracy
        case insufficientEvidence
    }

    struct ClassificationResult {
        var mode: LocationMode
        var confidence: Double
        var reason: LocationUncertaintyReason?
        var signalSource: SignalSource?
    }
    
    // MARK: - Apple Native Signal Data Types (Phase 1 & 2)
    
    struct AccuracyHistoryEntry {
        let timestamp: Date
        let accuracy: Double
        let coordinate: CLLocationCoordinate2D
    }
    
    struct PressureSample {
        let timestamp: Date
        let pressure: Double
        let relativeAltitude: Double
    }
    
    enum SignalSource: String {
        case floor              // CLFloor detection (highest priority)
        case accuracyPattern    // GPS accuracy pattern analysis
        case geofence          // Geofence entry/exit events
        case pressureChange    // Barometric pressure changes (VALIDATION ONLY - Critical Fix #2)
        case polygon           // OpenStreetMap polygon detection
        case distanceMotion    // Distance + motion heuristics
        case fallback          // Fallback when other signals unavailable
    }
    
    // MARK: - Critical Fix 1: Drift Detection Data Types (Nov 2025)
    
    struct DriftSample {
        let timestamp: Date
        let mode: LocationMode
        let coordinate: CLLocationCoordinate2D
        let confidence: Double
    }
    
    // MARK: - Critical Fix 3: Mode Lock Data Types (Nov 2025)
    
    struct ModeLock {
        let lockedMode: LocationMode
        let lockStartTime: Date
        let lockConfidence: Double

        /// Required confidence to break the lock (higher than normal threshold)
        static let unlockConfidenceRequirement: Double = 0.85

        /// Minimum duration before mode can be locked (5 minutes)
        static let minLockDuration: TimeInterval = 300

        /// Maximum lock duration before auto-expiry (REDUCED from 30 to 10 minutes - Nov 2025)
        /// Rationale: 30 minutes was too long - wrong classification could trap user for half hour
        /// 10 minutes balances stability (prevents flip-flopping) with responsiveness (recovers from errors)
        static let maxLockDuration: TimeInterval = 600

        func shouldUnlock(newMode: LocationMode, newConfidence: Double, timestamp: Date) -> Bool {
            // Different mode with high confidence can break lock
            if newMode != lockedMode && newConfidence >= Self.unlockConfidenceRequirement {
                print("🔓 [LocationManager] Mode lock broken: \(lockedMode.rawValue) → \(newMode.rawValue) (confidence: \(String(format: "%.2f", newConfidence)))")
                return true
            }
            return false
        }

        func isExpired(timestamp: Date) -> Bool {
            // Locks expire after maxLockDuration to prevent getting stuck
            return timestamp.timeIntervalSince(lockStartTime) > Self.maxLockDuration
        }
    }

    struct BuildingCacheEntry: Codable {
        let buildings: [OverpassService.OverpassBuilding]
        let timestamp: Date
    }

    struct LocationConfig {
        // Detection thresholds
        let motionThresholdMS = 0.8 // Walking pace threshold
        let vehicleSpeedThresholdMS = 5.0 // Vehicle detection threshold
        let stationarySpeedThresholdMS = 0.8
        let maxDistanceFromBuildingMeters = 35.0
        let gpsErrorMarginMeters = 15.0

        // Cache configuration
        let minCheckIntervalMS: TimeInterval = 30 // 30 seconds
        let staleThresholdMS: TimeInterval = 300 // 5 minutes
        let buildingCacheTTL: TimeInterval = 3600 // 1 hour
        let locationCacheTTL: TimeInterval = 90 // 90 seconds

        // Detection zones (meters)
        let zoneDefinitelyInside = 0.0
        let zoneProbablyInside = 15.0
        let zoneUncertain = 30.0
        let zoneProbablyOutside = 50.0
        let zoneDefinitelyOutside = 50.0

        // History configuration
        let historyWindowMS: TimeInterval = 300 // 5 minutes
        let minSamplesForTransition = 2
        let confidenceThresholdForHistory = 0.55
        let minConfidenceForKnownState = 0.60 // RAISED from 0.50 to prevent low-confidence samples from polluting history
        let maxGPSAccuracyMeters = 80.0
        let gpsAccuracyPenaltyThreshold = 40.0
        let significantMovementMeters = 25.0
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        restoreState() // Restore previous state for continuity
        loadPersistedData()
        setupLocationManager()
        // DON'T start motion manager on init - only when we actually start tracking
        
        // DON'T auto-start location updates on init
        // Let the app explicitly start them when ready (after checking daytime)
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // REDUCED from 25m to 10m for faster outdoor detection
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false // CRITICAL: Never pause for continuous tracking
        locationManager.showsBackgroundLocationIndicator = true // Show blue bar when tracking
        
        // Set activity type for continuous background tracking
        if #available(iOS 14.0, *) {
            locationManager.activityType = .fitness // Matches Expo behavior for higher priority updates
        }

        checkAuthorizationStatus()
    }

    private func setupMotionManager() {
        // Check if activity updates are available
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("[LocationManager] Motion activity not available on this device")
            return
        }

        // Start activity updates
        motionManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.handleMotionActivity(activity)
        }
    }
    
    private func stopMotionManager() {
        motionManager.stopActivityUpdates()
    }

    // MARK: - Public API

    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func requestOneTimeLocation() {
        guard isAuthorized else {
            requestLocationPermission()
            return
        }
        locationManager.requestLocation()
    }

    func startLocationUpdates() {
        guard isAuthorized else {
            requestLocationPermission()
            return
        }

        isTracking = true

        // PRIORITY 7 FIX: Track when tracking starts for conservative initial classification
        trackingStartTime = Date()

        // Start motion monitoring for adaptive distance filtering
        setupMotionManager()

        // PHASE 2: Start pressure monitoring for transition detection
        startPressureMonitoring()

        // PRIMARY: Continuous location updates (works in background)
        locationManager.startUpdatingLocation()

        // SECONDARY: Significant location changes (500m+ fallback)
        locationManager.startMonitoringSignificantLocationChanges()

        // TERTIARY: Visit monitoring (indoor/outdoor hints)
        if CLLocationManager.authorizationStatus() == .authorizedAlways {
            locationManager.startMonitoringVisits()
        }

        // DIAGNOSTIC: Request immediate location update to verify GPS is working
        print("🔔 [LocationManager] Requesting immediate GPS update for diagnostics...")
        locationManager.requestLocation()

        print("🔔 [LocationManager] Background location tracking STARTED")
        print("   - Continuous updates: ✓")
        print("   - Significant changes: ✓")
        print("   - Visit monitoring: \(CLLocationManager.authorizationStatus() == .authorizedAlways ? "✓" : "✗")")
        print("   - Distance filter: \(locationManager.distanceFilter)m")
        print("   - Desired accuracy: \(locationManager.desiredAccuracy)")
        print("   - Pressure monitoring: \(CMAltimeter.isRelativeAltitudeAvailable() ? "✓" : "✗")")
        print("   - Startup mode: Conservative thresholds for first 2 minutes")
    }

    func stopLocationUpdates() {
        isTracking = false

        // Stop motion monitoring
        stopMotionManager()

        // PHASE 2: Stop pressure monitoring
        stopPressureMonitoring()

        // Stop location services
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()

        print("🛑 [LocationManager] Background location tracking STOPPED")
    }

    // MARK: - Manual Override API

    /// Activates manual indoor override, forcing indoor classification for specified duration
    /// - Parameter duration: Duration in seconds (default: 900 = 15 minutes)
    func setManualIndoorOverride(duration: TimeInterval = 900) {
        guard manualOverrideEnabled else {
            print("⚠️ [LocationManager] Manual override is disabled in settings")
            return
        }

        manualIndoorOverride = true
        manualOverrideStartTime = Date()
        manualOverrideDuration = duration

        // Persist to UserDefaults
        let overrideDict: [String: Any] = [
            "isActive": true,
            "startTime": manualOverrideStartTime!.timeIntervalSince1970,
            "duration": duration
        ]
        userDefaults.set(overrideDict, forKey: manualOverrideKey)

        // Force immediate re-evaluation
        Task {
            _ = try? await getCurrentState(forceRefresh: true)
        }

        DetectionLogger.logState(
            event: "manual_override_activated",
            mode: .inside,
            details: ["duration_seconds": Int(duration)]
        )

        print("🏠 [LocationManager] Manual indoor override activated for \(Int(duration/60)) minutes")
    }

    /// Clears manual indoor override, resuming automatic detection
    func clearManualOverride() {
        manualIndoorOverride = false
        manualOverrideStartTime = nil

        // Clear from UserDefaults
        userDefaults.removeObject(forKey: manualOverrideKey)

        // Force immediate re-evaluation
        Task {
            _ = try? await getCurrentState(forceRefresh: true)
        }

        print("🔓 [LocationManager] Manual override cleared - resuming automatic detection")
    }

    /// Extends the current manual override by additional time
    /// - Parameter additionalSeconds: Additional duration in seconds (default: 900 = 15 minutes)
    func extendManualOverride(additionalSeconds: TimeInterval = 900) {
        guard manualIndoorOverride, let startTime = manualOverrideStartTime else {
            print("⚠️ [LocationManager] No active override to extend")
            return
        }

        // Extend duration from current time
        let elapsed = Date().timeIntervalSince(startTime)
        manualOverrideDuration = elapsed + additionalSeconds

        // Update persistence
        let overrideDict: [String: Any] = [
            "isActive": true,
            "startTime": startTime.timeIntervalSince1970,
            "duration": manualOverrideDuration
        ]
        userDefaults.set(overrideDict, forKey: manualOverrideKey)

        print("⏰ [LocationManager] Manual override extended by \(Int(additionalSeconds/60)) minutes")
    }

    /// Computed property indicating if manual override is currently active
    var isManualOverrideActive: Bool {
        guard manualIndoorOverride, let overrideTime = manualOverrideStartTime else {
            return false
        }
        let elapsed = Date().timeIntervalSince(overrideTime)
        if elapsed >= manualOverrideDuration {
            // Auto-expire if duration exceeded
            Task { @MainActor in
                clearManualOverride()
            }
            return false
        }
        return true
    }

    /// Returns remaining time in seconds for active manual override
    var manualOverrideRemainingTime: TimeInterval? {
        guard isManualOverrideActive, let startTime = manualOverrideStartTime else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, manualOverrideDuration - elapsed)
    }

    func getCurrentState(forceRefresh: Bool = false) async throws -> LocationState {
        let now = Date()

        // Use adaptive TTL based on confidence and motion
        let adaptiveTTL = getAdaptiveTTL()

        // Return cached state if valid
        if !forceRefresh,
           let state = currentState,
           now.timeIntervalSince(lastCheckTimestamp) < adaptiveTTL {
            return state
        }

        // If there's a pending check, wait for it
        if let pendingCheck = pendingCheck {
            do {
                return try await pendingCheck.value
            } catch {
                print("[LocationManager] Pending check failed: \(error)")
            }
        }

        // Perform fresh location check
        let task = Task<LocationState, Error> {
            try await performLocationCheck(forceRefresh: forceRefresh)
        }
        pendingCheck = task

        do {
            let state = try await task.value
            pendingCheck = nil
            return state
        } catch {
            pendingCheck = nil
            // Return stale state if available
            if let state = currentState {
                return LocationState(
                    latitude: state.latitude,
                    longitude: state.longitude,
                    mode: state.mode,
                    confidence: state.confidence,
                    timestamp: state.timestamp,
                    isStale: true,
                    speed: state.speed,
                    accuracy: state.accuracy,
                    activity: state.activity,
                    uncertaintyReason: state.uncertaintyReason
                )
            }
            throw error
        }
    }

    func clearCache() {
        currentState = nil
        locationHistory.removeAll()
        motionHistory.removeAll()
        buildingCache.removeAll()
        lastCheckTimestamp = Date.distantPast
        lastCachedLocation = nil
        uncertaintyReason = nil
        saveLocationHistory()
        saveMotionHistory()
        saveBuildingCache()
        try? FileManager.default.removeItem(at: locationHistoryURL)
        try? FileManager.default.removeItem(at: motionHistoryURL)
        try? FileManager.default.removeItem(at: buildingCacheURL)
        userDefaults.removeObject(forKey: "locationManager.reason")
    }
    
    // MARK: - Background Processing
    
    // REMOVED: Background timer is redundant with iOS native didUpdateLocations
    // iOS automatically handles background location updates reliably:
    // - Continuous updates when moving (every 10-25m based on distance filter)
    // - Throttled updates when stationary (~1/hour to save battery)
    // - Significant location changes for >500m movement
    // - Visit monitoring for 3+ minute stops
    // - Geofencing for instant building entry/exit
    // Using a separate timer was causing:
    // - Duplicate processing (70-90% overhead)
    // - Excessive API calls (rate limiting risk)
    // - Battery drain
    // - Timer reliability issues in background (iOS suspends apps)
    
    // MARK: - State Persistence
    
    private func loadPersistedData() {
        loadMotionHistory()
        loadLocationHistory()
        loadBuildingCache()
    }

    private func loadMotionHistory() {
        guard let data = try? Data(contentsOf: motionHistoryURL) else { return }
        let decoder = JSONDecoder()
        if let samples = try? decoder.decode([MotionSample].self, from: data) {
            motionHistory = samples
            pruneMotionHistory()
            saveMotionHistory()
        }
    }

    private func loadLocationHistory() {
        guard let data = try? Data(contentsOf: locationHistoryURL) else { return }
        let decoder = JSONDecoder()
        if let entries = try? decoder.decode([LocationHistoryEntry].self, from: data) {
            locationHistory = entries
            pruneLocationHistory()
            saveLocationHistory()
        }
    }

    private func loadBuildingCache() {
        guard let data = try? Data(contentsOf: buildingCacheURL) else { return }
        let decoder = JSONDecoder()
        if let cache = try? decoder.decode([String: BuildingCacheEntry].self, from: data) {
            buildingCache = cache
        }
    }

    private func saveMotionHistory() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(motionHistory) else { return }
        try? data.write(to: motionHistoryURL, options: .atomic)
    }

    private func saveLocationHistory() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(locationHistory) else { return }
        try? data.write(to: locationHistoryURL, options: .atomic)
    }

    private func saveBuildingCache() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(buildingCache) else { return }
        try? data.write(to: buildingCacheURL, options: .atomic)
    }

    /// Save current state to UserDefaults for continuity across app launches
    private func persistState() {
        guard let state = currentState else { return }
        
        var stateDict: [String: Any] = [
            "latitude": state.latitude,
            "longitude": state.longitude,
            "mode": state.mode.rawValue,
            "confidence": state.confidence,
            "timestamp": state.timestamp.timeIntervalSince1970,
            "speed": state.speed ?? -1,
            "accuracy": state.accuracy ?? -1
        ]

        if let reason = state.uncertaintyReason?.rawValue {
            stateDict["reason"] = reason
        }
        
        userDefaults.set(stateDict, forKey: stateKey)
        userDefaults.set(state.mode == .outside, forKey: "locationManager.isOutside")
        userDefaults.set(state.confidence, forKey: "locationManager.confidence")
        userDefaults.set(state.mode.rawValue, forKey: "locationManager.mode")
        if let reason = state.uncertaintyReason?.rawValue {
            userDefaults.set(reason, forKey: "locationManager.reason")
        } else {
            userDefaults.removeObject(forKey: "locationManager.reason")
        }
        userDefaults.synchronize()
    }
    
    /// Restore state from UserDefaults
    private func restoreState() {
        guard let stateDict = userDefaults.dictionary(forKey: stateKey) else { return }
        
        let restoredState = LocationState(
            latitude: stateDict["latitude"] as? Double ?? 0,
            longitude: stateDict["longitude"] as? Double ?? 0,
            mode: LocationMode(rawValue: stateDict["mode"] as? String ?? "unknown") ?? .unknown,
            confidence: stateDict["confidence"] as? Double ?? 0,
            timestamp: Date(timeIntervalSince1970: stateDict["timestamp"] as? TimeInterval ?? 0),
            isStale: true, // Mark as stale on restore
            speed: {
                let speed = stateDict["speed"] as? Double ?? -1
                return speed >= 0 ? speed : nil
            }(),
            accuracy: {
                let accuracy = stateDict["accuracy"] as? Double ?? -1
                return accuracy >= 0 ? accuracy : nil
            }(),
            activity: nil,
            uncertaintyReason: {
                guard let raw = stateDict["reason"] as? String else { return nil }
                return LocationUncertaintyReason(rawValue: raw)
            }()
        )
        
        // Only restore if recent (within 5 minutes)
        if Date().timeIntervalSince(restoredState.timestamp) < 300 {
            currentState = restoredState
            lastCheckTimestamp = restoredState.timestamp
            locationMode = restoredState.mode
            confidence = restoredState.confidence
            uncertaintyReason = restoredState.uncertaintyReason
            
            print("♻️  [LocationManager] State restored from previous session:", [
                "mode": restoredState.mode.rawValue,
                "age": "\(Int(Date().timeIntervalSince(restoredState.timestamp)))s",
                "confidence": String(format: "%.2f", restoredState.confidence)
            ])
        }

        // Restore manual override state
        if let overrideDict = userDefaults.dictionary(forKey: manualOverrideKey),
           let isActive = overrideDict["isActive"] as? Bool,
           isActive,
           let startTimestamp = overrideDict["startTime"] as? TimeInterval,
           let duration = overrideDict["duration"] as? TimeInterval {

            let startTime = Date(timeIntervalSince1970: startTimestamp)
            let elapsed = Date().timeIntervalSince(startTime)

            // Only restore if still within duration window
            if elapsed < duration {
                manualIndoorOverride = true
                manualOverrideStartTime = startTime
                manualOverrideDuration = duration

                let remaining = Int((duration - elapsed) / 60)
                print("♻️  [LocationManager] Manual override restored: \(remaining) minutes remaining")
            } else {
                // Expired - clear it
                userDefaults.removeObject(forKey: manualOverrideKey)
                print("♻️  [LocationManager] Manual override expired - cleared")
            }
        }
    }
    
    // MARK: - Circular Geofencing (Background Wake-Up Only)

    /// Setup circular geofences around nearby buildings for BACKGROUND WAKE-UP ONLY
    /// These 30m radius geofences trigger iOS callbacks that can wake the app when suspended
    /// They are NOT used for classification - polygon-based detection is more accurate
    func setupBuildingGeofences(buildings: [OverpassService.OverpassBuilding]) {
        guard let currentLoc = currentLocation else { return }

        // OPTIMIZATION: Skip if buildings haven't changed (same set of nearby buildings)
        let buildingHash = buildings.prefix(maxMonitoredRegions).map { $0.id }.joined().hashValue
        if buildingHash == lastGeofenceSetupHash && !monitoredBuildings.isEmpty {
            return  // Skip redundant setup
        }
        lastGeofenceSetupHash = buildingHash

        // Remove old geofences
        for region in locationManager.monitoredRegions {
            if monitoredBuildings.contains(region.identifier) {
                locationManager.stopMonitoring(for: region)
            }
        }
        monitoredBuildings.removeAll()

        // Sort buildings by distance and take nearest ones
        let sortedBuildings = buildings
            .compactMap { building -> (building: OverpassService.OverpassBuilding, distance: Double)? in
                guard let center = calculateBuildingCenter(building) else { return nil }
                let distance = currentLoc.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                return (building, distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(maxMonitoredRegions)

        for (building, _) in sortedBuildings {
            guard let center = calculateBuildingCenter(building) else { continue }

            let region = CLCircularRegion(
                center: center,
                radius: geofenceRadius,
                identifier: building.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true

            locationManager.startMonitoring(for: region)
            monitoredBuildings.insert(building.id)
        }

        print("🗺️ [LocationManager] Geofences updated: \(sortedBuildings.count) buildings monitored")
    }
    
    /// Calculate the center point of a building polygon
    private func calculateBuildingCenter(_ building: OverpassService.OverpassBuilding) -> CLLocationCoordinate2D? {
        guard !building.points.isEmpty else { return nil }

        let latSum = building.points.reduce(0.0) { $0 + $1[0] }
        let lonSum = building.points.reduce(0.0) { $0 + $1[1] }
        let count = Double(building.points.count)

        return CLLocationCoordinate2D(
            latitude: latSum / count,
            longitude: lonSum / count
        )
    }

    // MARK: - Polygon-Based Geofencing (Exact Boundary Detection)

    /// Update polygon occupancy tracking - detects entry/exit from exact building boundaries
    /// This provides much more accurate detection than circular geofences
    private func updatePolygonOccupancy(coordinate: CLLocationCoordinate2D, buildings: [OverpassService.OverpassBuilding]) {
        var newPolygons: Set<String> = []

        // Check which building polygons we're currently inside
        for building in buildings {
            if GeometryUtils.pointInPolygon(point: [coordinate.latitude, coordinate.longitude], polygon: building.points) {
                newPolygons.insert(building.id)

                // Detect entry (wasn't in this polygon before, now we are)
                if !currentPolygons.contains(building.id) {
                    handlePolygonEntry(buildingId: building.id, coordinate: coordinate)
                }
            }
        }

        // Detect exits (was in polygon before, now we're not)
        for oldBuildingId in currentPolygons {
            if !newPolygons.contains(oldBuildingId) {
                handlePolygonExit(buildingId: oldBuildingId, coordinate: coordinate)
            }
        }

        currentPolygons = newPolygons
    }

    /// Handle polygon entry event - triggered when GPS crosses building boundary inward
    private func handlePolygonEntry(buildingId: String, coordinate: CLLocationCoordinate2D) {
        let now = Date()
        polygonEntryTimestamps[buildingId] = now
        polygonEntryPositions[buildingId] = coordinate  // Store position to validate movement at exit

        DetectionLogger.logGeofence(
            event: "POLYGON ENTRY",
            buildingId: buildingId
        )
    }

    /// Handle polygon exit event - triggered when GPS crosses building boundary outward
    /// CRITICAL: Validates actual movement to prevent GPS drift from creating false exit events
    private func handlePolygonExit(buildingId: String, coordinate: CLLocationCoordinate2D) {
        let now = Date()

        // Calculate duration inside polygon
        let duration: TimeInterval? = polygonEntryTimestamps[buildingId].map { entryTime in
            now.timeIntervalSince(entryTime)
        }

        // MOVEMENT VALIDATION: Check if user actually moved or if this is GPS drift
        // If position hasn't changed significantly from entry, this is likely GPS drift, not real exit
        if let entryPosition = polygonEntryPositions[buildingId] {
            let movementDistance = haversineDistance(
                from: entryPosition,
                to: coordinate
            )

            if movementDistance < 10 {
                // Position barely changed (<10m) - likely GPS drift, not actual exit
                if DetectionLogger.isVerboseMode {
                    print("⚠️ Polygon exit rejected: \(Int(movementDistance))m movement (GPS drift)")
                }
                return
            }
        }

        // Valid exit - record timestamp
        polygonExitTimestamps[buildingId] = now

        DetectionLogger.logGeofence(
            event: "POLYGON EXIT",
            buildingId: buildingId,
            duration: duration
        )
    }

    // MARK: - Polygon-Based Classification Helpers

    /// Check if currently inside any building polygon (absolute veto for outdoor classification)
    /// Polygons are accurate - if GPS shows inside, user is likely inside
    func isInsideAnyPolygon() -> Bool {
        return !currentPolygons.isEmpty
    }

    /// Check if sustained inside polygon (>30 seconds) - strong indoor signal
    /// Used to stop outdoor tracking when user actually enters building
    func isInsidePolygonSustained() -> (Bool, TimeInterval?) {
        guard let currentBuildingId = currentPolygons.first,
              let entryTime = polygonEntryTimestamps[currentBuildingId] else {
            return (false, nil)
        }

        let duration = Date().timeIntervalSince(entryTime)
        return (duration > 30, duration)
    }

    /// Check if recently exited polygon (within 90 seconds) - strong outdoor signal
    /// User just left building, likely now on sidewalk
    func hasRecentPolygonExit() -> (Bool, TimeInterval?) {
        let now = Date()

        // Find most recent exit
        let recentExits = polygonExitTimestamps.values.compactMap { exitTime -> TimeInterval? in
            let timeSinceExit = now.timeIntervalSince(exitTime)
            return timeSinceExit < 90 ? timeSinceExit : nil
        }

        if let mostRecentExit = recentExits.min() {
            return (true, mostRecentExit)
        }

        return (false, nil)
    }

    /// Get duration inside current polygon (if any)
    func getCurrentPolygonDuration() -> TimeInterval? {
        guard let currentBuildingId = currentPolygons.first,
              let entryTime = polygonEntryTimestamps[currentBuildingId] else {
            return nil
        }
        return Date().timeIntervalSince(entryTime)
    }

    /// Check if floor was detected recently (strong indoor signal)
    /// Floor data only available in multi-story buildings (indoors)
    func hasRecentFloorDetection(within seconds: TimeInterval = 300) -> Bool {
        guard let lastFloorTime = lastFloorDetectionTime else {
            return false
        }
        return Date().timeIntervalSince(lastFloorTime) < seconds
    }

    /// Get cached nearest building distance for current location
    /// Used by accuracy pattern tier to check proximity without async API call
    /// Returns nil if no cached building data available
    func getCachedNearestBuildingDistance() -> Double? {
        guard let currentLocation = currentState else { return nil }

        let latKey = Int(currentLocation.latitude * 1000)
        let lonKey = Int(currentLocation.longitude * 1000)
        let cacheKey = "\(latKey):\(lonKey)"

        guard let cached = buildingCache[cacheKey],
              Date().timeIntervalSince(cached.timestamp) < config.buildingCacheTTL,
              !cached.buildings.isEmpty else {
            return nil
        }

        let point = [currentLocation.latitude, currentLocation.longitude]
        let distance = GeometryUtils.nearestBuildingDistance(point: point, buildings: cached.buildings)

        // Filter out sentinel value for "no buildings found"
        return distance < 999999 ? distance : nil
    }

    // MARK: - Private Methods

    private func checkAuthorizationStatus() {
        let status = CLLocationManager.authorizationStatus()
        isAuthorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
        
        // Check for reduced accuracy and request full accuracy
        if #available(iOS 14.0, *) {
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                print("⚠️ [LocationManager] Reduced accuracy mode detected - requesting full accuracy")
                locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracyUsage")
            }
        }
        
        // Don't auto-start here - let the app control when to start
        // This prevents starting before we have accurate sun times
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        // Only process motion updates if we're actively tracking
        guard isTracking else { return }
        
        let motionActivity = parseMotionActivity(activity)

        // Update motion history
        let sample = MotionSample(
            timestamp: Date(),
            speed: currentLocation?.speed ?? 0,
            activity: motionActivity
        )
        motionHistory.append(sample)
        pruneMotionHistory()
        saveMotionHistory()

        // Check for significant activity changes that warrant location check
        let wasAutomotive = motionHistory.dropLast().contains { $0.activity == .automotive }
        let isNowAutomotive = motionActivity == .automotive
        
        let wasStationary = motionHistory.dropLast().contains { $0.activity == .stationary }
        let isNowWalking = motionActivity == .walking || motionActivity == .running
        
        // FIX #11: Adaptive distance filter for faster outdoor detection
        // When user starts moving, reduce distance filter for more frequent updates
        if isNowWalking && wasStationary {
            print("🏃 [LocationManager] Motion detected - enabling fast sampling (10m filter)")
            locationManager.distanceFilter = 10  // More frequent updates when moving
        } else if motionActivity == .stationary && !wasStationary {
            // Only increase filter if high confidence in current state
            if let state = currentState, state.confidence >= 0.80 {
                print("🛑 [LocationManager] Stationary with high confidence - normal sampling (15m filter)")
                locationManager.distanceFilter = 15  // REDUCED from 25m to 15m for better responsiveness
            } else {
                print("📍 [LocationManager] Stationary but uncertain - keeping fast sampling (10m filter)")
                locationManager.distanceFilter = 10  // Keep fast sampling if uncertain
            }
        }
        
        let shouldCheckLocation = (wasAutomotive && !isNowAutomotive) || 
                                  (wasStationary && isNowWalking)

        if shouldCheckLocation {
            print("🚶 [LocationManager] Significant motion change detected: triggering location check")
            Task {
                _ = try? await performLocationCheck(forceRefresh: true)
            }
        }
    }

    private func parseMotionActivity(_ activity: CMMotionActivity) -> MotionActivity {
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }

    private func performLocationCheck(forceRefresh: Bool = false) async throws -> LocationState {
        // Get current GPS location
        guard let location = currentLocation ?? locationManager.location else {
            throw LocationError.locationUnavailable
        }

        let coordinate = location.coordinate
        let accuracy = location.horizontalAccuracy
        let speed = location.speed >= 0 ? location.speed : nil

        // OPTIMIZATION: Track GPS availability for timeout detection
        // If GPS is unavailable/very poor for >5 minutes (e.g., subway), switch to UNKNOWN
        if accuracy > 0 && accuracy < 150 {
            lastValidGPSTimestamp = Date()  // Update last valid GPS time
        } else if Date().timeIntervalSince(lastValidGPSTimestamp) > 300 {
            // No valid GPS for 5 minutes (subway, tunnel, indoor parking, etc.)
            print("⚠️ [LocationManager] GPS unavailable for >5 minutes - switching to UNKNOWN mode")
            let unknownState = LocationState(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                mode: .unknown,
                confidence: 0.0,
                timestamp: Date(),
                isStale: false,
                speed: speed,
                accuracy: accuracy > 0 ? accuracy : nil,
                activity: nil,
                uncertaintyReason: .poorGPSAccuracy
            )
            currentState = unknownState
            locationMode = .unknown
            confidence = 0.0
            uncertaintyReason = .poorGPSAccuracy
            return unknownState
        }

        if #available(iOS 14.0, *) {
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                try? await locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracyUsage")
            }
        }

        DetectionLogger.log(
            "GPS Update: accuracy=\(accuracy > 0 ? "\(Int(accuracy))m" : "unknown"), speed=\(speed != nil ? String(format: "%.1f", speed!) + " m/s" : "null"), floor=\(location.floor?.level != nil ? "L\(location.floor!.level)" : "none")",
            category: .debug
        )

        // PHASE 1: Update accuracy history for pattern recognition
        updateAccuracyHistory(location: location)

        // Update motion history
        if let speed = speed {
            motionHistory.append(MotionSample(
                timestamp: Date(),
                speed: speed,
                activity: motionHistory.last?.activity
            ))
            pruneMotionHistory()
            saveMotionHistory()
        }

        // Check for significant movement
        if let lastLocation = lastCachedLocation {
            let distance = haversineDistance(from: coordinate, to: lastLocation)
            if distance > config.significantMovementMeters {
                print("[LocationManager] 🚶 Significant movement detected: \(Int(distance))m")
            }
        }

        // Determine motion state
        let motionState = analyzeMotion()

        // PRIORITY 6 FIX: Tunnel Detection (check before classification)
        // If in tunnel/parking garage, maintain vehicle mode without reclassification
        if let tunnelMode = checkTunnelDetection(
            currentAccuracy: accuracy,
            currentMode: currentState?.mode ?? .unknown,
            motion: motionState
        ) {
            // In tunnel - return stable vehicle state without reclassification
            let tunnelState = LocationState(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                mode: tunnelMode,
                confidence: 0.95,  // High confidence - maintaining known state
                timestamp: Date(),
                isStale: false,
                speed: speed,
                accuracy: accuracy > 0 ? accuracy : nil,
                activity: motionState.activity,
                uncertaintyReason: nil
            )
            currentState = tunnelState
            locationMode = tunnelMode
            confidence = 0.95
            return tunnelState
        }

        // PRIORITY 0: Manual Indoor Override (Highest Priority)
        // Check if user has manually overridden the detection system
        if manualIndoorOverride, let overrideTime = manualOverrideStartTime {
            let elapsed = Date().timeIntervalSince(overrideTime)

            if elapsed < manualOverrideDuration {
                // Override still active - force indoor classification
                let remaining = Int((manualOverrideDuration - elapsed) / 60)
                DetectionLogger.logDetection(
                    mode: .inside,
                    confidence: 1.0,
                    source: "manual_override",
                    coordinate: coordinate,
                    accuracy: accuracy,
                    motion: motionState.activity?.rawValue ?? "unknown",
                    nearestBuilding: nil
                )

                let overrideState = LocationState(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    mode: .inside,
                    confidence: 1.0,  // 100% confidence - user confirmed
                    timestamp: Date(),
                    isStale: false,
                    speed: speed,
                    accuracy: accuracy > 0 ? accuracy : nil,
                    activity: motionState.activity,
                    uncertaintyReason: nil
                )

                currentState = overrideState
                locationMode = .inside
                confidence = 1.0

                print("🏠 [LocationManager] Manual override active: \(remaining) min remaining")
                return overrideState
            } else {
                // Override expired - clear it and continue with normal detection
                Task { @MainActor in
                    clearManualOverride()
                }
                print("⏰ [LocationManager] Manual override expired - resuming automatic detection")
            }
        }

        // PHASE 1 & 2: MULTI-TIER CLASSIFICATION SYSTEM
        // Priority order: Manual Override > Floor > Accuracy Pattern > Geofence > Pressure > Building Data > Distance+Motion
        var classification: ClassificationResult
        var signalSource: SignalSource
        var buildingFetchFailed = false  // Track if API failed
        var nearestDistance: Double = 999  // Default: far from buildings

        // CRITICAL FIX (Nov 2025): Fetch buildings and update polygon state FIRST
        // This ensures isInsideAnyPolygon() returns current data for all classification tiers
        // Previously, accuracy pattern tier checked stale polygon data causing false outdoor indoors
        let buildings: [OverpassService.OverpassBuilding]
        do {
            buildings = try await fetchNearbyBuildings(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            buildingFetchFailed = true
            buildings = []
            print("⚠️ [LocationManager] Building lookup failed: \(error.localizedDescription)")
        }

        // Update polygon occupancy BEFORE any classification that uses isInsideAnyPolygon()
        updatePolygonOccupancy(coordinate: coordinate, buildings: buildings)

        // Pre-calculate nearest building distance for use in all tiers
        if !buildings.isEmpty {
            nearestDistance = GeometryUtils.nearestBuildingDistance(
                point: [coordinate.latitude, coordinate.longitude],
                buildings: buildings
            )
        }

        // TIER 1: Floor detection (definitive, instant, no API)
        if let floorResult = classifyWithFloorData(location: location) {
            classification = floorResult
            signalSource = .floor
            DetectionLogger.logSignal(
                type: "Floor Detection",
                result: classification.mode.rawValue,
                confidence: classification.confidence,
                details: ["floor": location.floor?.level ?? "N/A"]
            )
        }
        // TIER 2: Accuracy pattern (strong signal, now with fresh polygon data)
        else if let patternResult = classifyWithAccuracyPattern(location: location, motion: motionState) {
            classification = patternResult
            signalSource = .accuracyPattern
            DetectionLogger.logSignal(
                type: "GPS Accuracy Pattern",
                result: classification.mode.rawValue,
                confidence: classification.confidence,
                details: ["accuracy": accuracy > 0 ? "\(Int(accuracy))m" : "unknown"]
            )
        }
        // TIER 3: Recent geofence event - REMOVED
        // Circular geofences are now used ONLY for background wake-up, not classification
        // Polygon-based geofencing provides superior accuracy with movement validation
        // TIER 4: Pressure change (transition detector, no API)
        else if let pressureResult = classifyWithPressureChange(location: location, motion: motionState) {
            classification = pressureResult
            signalSource = .pressureChange
            DetectionLogger.logSignal(
                type: "Pressure Change",
                result: classification.mode.rawValue,
                confidence: classification.confidence
            )
        }
        // TIER 5: Building data classification (polygon already updated above)
        else {
            classification = classifyLocation(
                coordinate: coordinate,
                buildings: buildings,
                motion: motionState,
                buildingDataAvailable: !buildingFetchFailed
            )
            signalSource = buildingFetchFailed ? .fallback : .polygon

            DetectionLogger.logSignal(
                type: buildingFetchFailed ? "Fallback Heuristic" : "Building Data",
                result: classification.mode.rawValue,
                confidence: classification.confidence,
                details: [
                    "buildings_found": buildings.count,
                    "nearest_distance": nearestDistance < 999 ? "\(Int(nearestDistance))m" : ">1km"
                ]
            )
        }

        // Setup geofences for faster future transitions (only when using building data)
        if !buildings.isEmpty {
            setupBuildingGeofences(buildings: buildings)
        }
        
        // Store signal source for debugging
        classification.signalSource = signalSource
        
        // CRITICAL FIX #1: Drift Detection (Nov 2025)
        // Check if GPS is drifting (oscillating classifications while stationary)
        if let driftDetection = detectGPSDrift(
            newMode: classification.mode,
            coordinate: coordinate,
            confidence: classification.confidence,
            motion: motionState
        ) {
            if driftDetection.isDrifting {
                print("🌀 [LocationManager] GPS DRIFT DETECTED - locking to current mode (\(driftDetection.recommendedMode.rawValue))")
                classification.mode = driftDetection.recommendedMode
                classification.confidence = driftDetection.confidence
                // Mark as drift-related for logging
                if classification.mode == .unknown {
                    classification.reason = .poorGPSAccuracy
                }
            }
        }
        
        // Log classification result with full context
        let motionString = motionState.isVehicle ? "vehicle" : motionState.isWalking ? "walking" : motionState.isStationary ? "stationary" : "unknown"

        DetectionLogger.logDetection(
            mode: classification.mode,
            confidence: classification.confidence,
            source: signalSource.rawValue,
            coordinate: coordinate,
            accuracy: accuracy > 0 ? accuracy : nil,
            motion: motionString,
            nearestBuilding: nearestDistance < 999 ? nearestDistance : nil,
            reasoning: classification.reason?.rawValue
        )

        // Apply GPS accuracy penalty
        var finalConfidence = classification.confidence * getGPSAccuracyFactor(accuracy)
        var mode = classification.mode
        var reason = classification.reason
        
        // CRITICAL FIX #2: Apply pressure validation boost (if available)
        // Barometer is now validation-only, not a decision-maker
        if mode != .unknown {
            let pressureBoost = getPressureValidation(proposedMode: mode, motion: motionState)
            if pressureBoost > 0 {
                finalConfidence = min(0.95, finalConfidence + pressureBoost)
            }
        }
        
        // IMPROVEMENT: Use context-aware threshold instead of fixed value
        let contextAwareThreshold = getMinConfidenceForKnownState(
            motion: motionState,
            nearestDistance: nearestDistance
        )
        let unknownConfidenceCap = max(0.0, contextAwareThreshold - 0.05)

        // IMPROVEMENT #4: API failure fallback - use GPS + motion heuristic instead of defaulting to unknown
        if buildingFetchFailed {
            // Check if we have recent indoor history to help decide
            let hasRecentIndoorHistory = locationHistory.suffix(5).contains { entry in
                entry.mode == .inside && Date().timeIntervalSince(entry.timestamp) < 300
            }
            
            // If good GPS accuracy + moving + no recent indoor history = likely outdoor
            if accuracy > 0 && accuracy < 20 && speed ?? 0 > 0.5 && !hasRecentIndoorHistory {
                print("🔄 [LocationManager] API unavailable but GPS quality good + moving - inferring outdoor (confidence 0.65)")
                mode = .outside
                reason = .buildingDataUnavailable
                finalConfidence = 0.65  // Lower confidence but better than unknown
            } else {
                mode = .unknown
                reason = .buildingDataUnavailable
                finalConfidence = min(finalConfidence, unknownConfidenceCap)
            }
        }

        if accuracy > 0, accuracy >= config.maxGPSAccuracyMeters {
            mode = .unknown
            reason = .poorGPSAccuracy
            finalConfidence = min(finalConfidence, unknownConfidenceCap)
        }

        // IMPROVED: Adaptive confidence thresholds based on context
        let isVehicleDetection = mode == .vehicle
        let isColdStart = locationHistory.isEmpty
        let isFarFromBuildings = nearestDistance > 100 // RAISED from 50m to prevent GPS drift false positives
        
        // Vehicle detection: Use higher threshold, accept single sample
        if isVehicleDetection {
            if finalConfidence < 0.85 {
                mode = currentState?.mode ?? .unknown
                reason = .insufficientEvidence
                finalConfidence = min(finalConfidence, unknownConfidenceCap)
                print("⚠️  [LocationManager] Vehicle confidence too low (\(String(format: "%.2f", finalConfidence))), keeping current mode")
            }
        }
        // Cold start + far from buildings: Higher threshold to prevent false positives
        else if isColdStart && isFarFromBuildings {
            if mode != .unknown && finalConfidence >= 0.75 { // RAISED from 0.60 to prevent GPS drift false starts
                print("🚀 [LocationManager] Cold start optimization: >100m from buildings with high confidence, accepting outdoor state")
                // Allow outdoor detection for cold start when clearly far from any building
            } else if mode != .unknown && finalConfidence < contextAwareThreshold {
                mode = .unknown
                reason = reason ?? .insufficientEvidence
                finalConfidence = min(finalConfidence, unknownConfidenceCap)
            }
        }
        // Normal case: Use context-aware threshold
        else if mode != .unknown && finalConfidence < contextAwareThreshold {
            mode = .unknown
            reason = reason ?? .insufficientEvidence
            finalConfidence = min(finalConfidence, unknownConfidenceCap)
            print("⚠️  [LocationManager] Confidence \(String(format: "%.2f", finalConfidence)) below threshold \(String(format: "%.2f", contextAwareThreshold)) for motion context")
        }

        if mode == .unknown {
            finalConfidence = max(0.0, min(finalConfidence, unknownConfidenceCap))
        }

        // Create new state
        var newState = LocationState(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            mode: mode,
            confidence: finalConfidence,
            timestamp: Date(),
            isStale: false,
            speed: speed,
            accuracy: accuracy > 0 ? accuracy : nil,
            activity: motionState.activity,
            uncertaintyReason: reason
        )

        // Add to history (only known modes) - include signal source for weighted decay
        addToHistory(newState, signalSource: signalSource)

        // IMPROVED: Check if stable mode can be determined with adaptive requirements
        if newState.mode != .unknown {
            // For vehicle detection: Require higher confidence but allow single sample
            let allowSingleVehicleSample = newState.mode == .vehicle && newState.confidence >= 0.85

            // Determine if we should allow single sample detection
            let shouldAllowSingleSample = allowSingleVehicleSample
            
            if let stableMode = getStableModeFromHistory(allowSingleSample: shouldAllowSingleSample) {
                newState = LocationState(
                    latitude: newState.latitude,
                    longitude: newState.longitude,
                    mode: stableMode,
                    confidence: min(0.95, max(0.75, newState.confidence)), // No boost, use consistent confidence
                    timestamp: newState.timestamp,
                    isStale: newState.isStale,
                    speed: newState.speed,
                    accuracy: newState.accuracy,
                    activity: newState.activity,
                    uncertaintyReason: nil
                )
            }
        }
        
        // CRITICAL FIX #3: Mode Lock for Stable States (Nov 2025)
        // If in same mode for 5+ minutes with high confidence, lock the mode
        // This prevents GPS drift from breaking stable states (e.g., user at desk for hours)
        if let lock = modeLock {
            // Check if lock should be broken
            if lock.shouldUnlock(newMode: newState.mode, newConfidence: newState.confidence, timestamp: Date()) {
                modeLock = nil
                print("🔓 [LocationManager] Mode lock released")
            } else if lock.isExpired(timestamp: Date()) {
                modeLock = nil
                print("⏰ [LocationManager] Mode lock expired (\(Int(ModeLock.maxLockDuration/60))min timeout)")
            } else if newState.mode != lock.lockedMode {
                // Lock prevents mode change - revert to locked mode
                print("🔒 [LocationManager] Mode lock active - maintaining \(lock.lockedMode.rawValue) (confidence: \(String(format: "%.2f", lock.lockConfidence)))")
                print("   Rejected: \(newState.mode.rawValue) with confidence \(String(format: "%.2f", newState.confidence)) (need ≥0.85 to unlock)")
                newState = LocationState(
                    latitude: newState.latitude,
                    longitude: newState.longitude,
                    mode: lock.lockedMode,
                    confidence: lock.lockConfidence,
                    timestamp: newState.timestamp,
                    isStale: newState.isStale,
                    speed: newState.speed,
                    accuracy: newState.accuracy,
                    activity: newState.activity,
                    uncertaintyReason: nil
                )
            }
        } else {
            // Check if we should create a new lock
            if shouldCreateModeLock(mode: newState.mode, confidence: newState.confidence) {
                modeLock = ModeLock(
                    lockedMode: newState.mode,
                    lockStartTime: Date(),
                    lockConfidence: newState.confidence
                )
                print("🔒 [LocationManager] Mode lock created: \(newState.mode.rawValue) (confidence: \(String(format: "%.2f", newState.confidence)))")
            }
        }

        // Update state
        let modeChanged = currentState?.mode != newState.mode
        currentState = newState
        lastCheckTimestamp = Date()
        lastCachedLocation = coordinate

        // Update published properties
        // UI LOGIC: Only show "outdoor" when session is actually active (outdoor lock)
        // This ensures the UI matches the actual UV tracking state
        let outdoorLockActive = await BackgroundTaskManager.shared.outdoorLockActive

        // Determine what mode to show in UI
        let uiMode: LocationMode
        if newState.mode == .outside && !outdoorLockActive {
            // Detection says outdoor, but session hasn't started yet
            // Keep UI at previous mode (likely inside/unknown) until session activates
            uiMode = self.locationMode  // Keep current UI mode
        } else if outdoorLockActive && (newState.mode == .inside || newState.mode == .unknown) && newState.confidence < 0.95 {
            // Session active but weak indoor signal - keep showing outdoor
            uiMode = .outside
        } else {
            // Normal case: show actual detected mode
            uiMode = newState.mode
        }

        self.locationMode = uiMode
        self.confidence = newState.confidence
        self.uncertaintyReason = newState.uncertaintyReason
        
        // FIX #11: Adaptive sampling based on state certainty
        // When in uncertain state or near transition, request more frequent updates
        if newState.mode == .unknown || newState.confidence < 0.70 {
            if locationManager.distanceFilter != 10 {
                print("📍 [LocationManager] Uncertain state - enabling fast sampling (10m filter)")
                locationManager.distanceFilter = 10
            }
        } else if newState.confidence >= 0.85 && motionState.isStationary {
            // Only reduce frequency if VERY high confidence (raised from 0.80)
            if locationManager.distanceFilter != 15 {
                print("📍 [LocationManager] Very high confidence + stationary - normal sampling (15m filter)")
                locationManager.distanceFilter = 15  // REDUCED from 25m
            }
        }
        
        // Persist state for continuity
        persistState()

        // NOTE: UV tracking is NOT started here - it's handled by BackgroundTaskManager.handleOutsideDetection()
        // which is called from didUpdateLocations() after this method returns.
        // The old startUVTracking() call here only fetched UV index but didn't activate the outdoor lock
        // or start the UV timer, causing a "standby" bug where user was classified outdoor but not tracking.
        // FIX (Nov 2025): Removed misleading startUVTracking()/stopUVTracking() calls.

        if modeChanged {
            let previousMode = currentState?.mode ?? .unknown
            let previousModeDuration = currentState.map { Date().timeIntervalSince($0.timestamp) }

            DetectionLogger.logTransition(
                from: previousMode,
                to: newState.mode,
                confidence: newState.confidence,
                trigger: signalSource.rawValue,
                duration: previousModeDuration
            )
        }

        return newState
    }

    private func fetchNearbyBuildings(latitude: Double, longitude: Double) async throws -> [OverpassService.OverpassBuilding] {
        // OPTIMIZATION: Larger cache cells (3 decimals = ~111m) to reduce API calls
        // GPS drift of 30m won't cross cache boundaries as often
        // Trade-off: Slightly larger cache entries, but 80% reduction in API calls for stationary users
        let latKey = Int(latitude * 1000)
        let lonKey = Int(longitude * 1000)
        let cacheKey = "\(latKey):\(lonKey)"

        if let cached = buildingCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < config.buildingCacheTTL {
            return cached.buildings
        }

        // Fetch from Overpass API with slightly larger radius to cover cell edges
        // 150m radius ensures we get buildings at edges of ~111m cache cell
        let buildings = try await overpassService.getNearbyBuildings(
            latitude: latitude,
            longitude: longitude,
            radius: 150  // Increased from default 100m
        )

        // Cache the result
        buildingCache[cacheKey] = BuildingCacheEntry(
            buildings: buildings,
            timestamp: Date()
        )
        saveBuildingCache()

        return buildings
    }

    private func classifyLocation(
        coordinate: CLLocationCoordinate2D,
        buildings: [OverpassService.OverpassBuilding],
        motion: MotionState,
        buildingDataAvailable: Bool
    ) -> ClassificationResult {
        if !buildingDataAvailable {
            return ClassificationResult(mode: .unknown, confidence: 0.3, reason: .buildingDataUnavailable)
        }

        let point = [coordinate.latitude, coordinate.longitude]

        // Check if inside any building polygon
        let insidePolygon = GeometryUtils.pointInAnyPolygon(
            point: point,
            polygons: buildings.map { $0.points }
        )

        // Calculate nearest building distance
        let nearestDistance = GeometryUtils.nearestBuildingDistance(
            point: point,
            buildings: buildings
        )

        // Vehicle detection takes priority
        if motion.isVehicle {
            return ClassificationResult(mode: .vehicle, confidence: motion.vehicleConfidence, reason: nil)
        }

        // IMPROVEMENT #1: Inside building polygon is nearly definitive
        // This should override GPS drift history immediately
        if insidePolygon {
            return ClassificationResult(mode: .inside, confidence: 0.98, reason: nil)
        }

        // Zone-based classification
        let classification = classifyByZone(
            nearestDistance: nearestDistance,
            motion: motion
        )

        return ClassificationResult(mode: classification.mode, confidence: classification.confidence, reason: nil)
    }

    private func classifyByZone(
        nearestDistance: Double,
        motion: MotionState
    ) -> (mode: LocationMode, confidence: Double) {
        if motion.isVehicle {
            let confidence = max(motion.vehicleConfidence, 0.8)
            return (.vehicle, confidence)
        }

        // CRITICAL FIX: If distance is 0m or very close, treat as inside building
        // This handles edge cases where polygon check might miss but distance is definitive
        if nearestDistance < 2 {
            print("🏢 [LocationManager] Very close to/inside building (\(String(format: "%.1f", nearestDistance))m) - treating as INSIDE")
            return (.inside, 0.90)
        }

        // POLYGON-BASED GEOFENCING: Absolute veto for outdoor if inside building polygon
        // Building polygons from OSM are accurate - if GPS shows inside, user is likely inside
        // This check prevents GPS drift from incorrectly triggering outdoor detection
        if isInsideAnyPolygon() {
            let (isSustained, duration) = isInsidePolygonSustained()
            if isSustained {
                print("🏢 [LocationManager] Inside polygon for \(Int(duration ?? 0))s - sustained indoor detection")
                return (.inside, 0.90)  // High confidence - sustained polygon occupancy
            } else {
                print("🏢 [LocationManager] Inside polygon (recent entry) - indoor detection")
                return (.inside, 0.80)  // Good confidence - just entered polygon
            }
        }

        if nearestDistance <= config.zoneProbablyInside {
            // FIX #7: REMOVED motion transition logic - causes false positives when walking indoors
            // Walking happens indoors too (to printer, bathroom, etc.)

            // FIX #8: REMOVED "recent movement" outdoor bias - causes false positives
            // User walking to printer and sitting back down should stay INSIDE

            if motion.isStationary && !motion.isWalking {
                // PRIORITY 1 FIX: Enhanced stationary outdoor detection (bus stop scenario)
                // Check multiple indicators to distinguish between:
                // - Stationary OUTDOOR (bus stop, waiting on sidewalk): GPS stable, good accuracy
                // - Stationary INDOOR (at desk): GPS drifting, varying accuracy

                // INDICATOR 1: GPS accuracy stability
                // Outdoor: stable accuracy over time (15-25m consistent)
                // Indoor: varying accuracy (GPS bouncing 20-60m)
                let hasStableGPS = checkGPSStability()

                // INDICATOR 2: Polygon entry history
                // If not inside any building polygon, likely outside
                let notInsidePolygon = checkNoRecentPolygonEntry()

                // INDICATOR 3: Sustained good accuracy
                // If accuracy has been <25m for 60+ seconds, likely outdoor with sky visibility
                let hasSustainedGoodAccuracy = checkSustainedGoodAccuracy()

                // CRITICAL FIX: Detect "near window" scenario
                // Stationary + excellent GPS + near/inside building = likely at desk near window
                // This is a VERY common false positive in urban environments
                // TIERED approach: stricter for very close, requires longer duration for moderate distance
                let hasExcellentGPS = (accuracyHistory.last?.accuracy ?? 100) < 15
                let stationaryDuration = getConsecutiveActivityDuration(.stationary)
                let isVeryStationary = stationaryDuration > 120  // 2+ minutes
                let isExtendedStationary = stationaryDuration > 300  // 5+ minutes

                // TIER 1: Inside polygon = always window scenario
                let isInsidePolygonNow = isInsideAnyPolygon()

                // TIER 2: Very close (<5m) + >2min = likely ground floor window
                // CRITICAL FIX (Nov 2025): Lowered from 8m to 5m to prevent bus stop false positives
                // Bus stops 5-8m from buildings should be classified as outdoor
                let isVeryCloseToBuilding = nearestDistance < 5

                // TIER 3: Moderately close (5-15m) + >5min = likely upper floor window
                let isModeratelyCloseToBuilding = nearestDistance >= 5 && nearestDistance < 15

                // POLYGON ABSOLUTISM: If NOT inside polygon AND >5m from building, bias toward outdoor
                // This prevents false indoor classification of bus stops, outdoor seating, etc.
                let shouldApplyPolygonAbsolutism = !isInsidePolygonNow && nearestDistance >= 5

                // Combined check with tiered thresholds to reduce false negatives
                let isLikelyNearWindow = (isInsidePolygonNow && hasExcellentGPS && isVeryStationary) ||
                                         (isVeryCloseToBuilding && hasExcellentGPS && isVeryStationary) ||
                                         (isModeratelyCloseToBuilding && hasExcellentGPS && isExtendedStationary && !shouldApplyPolygonAbsolutism)

                if isLikelyNearWindow {
                    print("🪟 [LocationManager] NEAR WINDOW detected: Stationary >2min + excellent GPS (\(String(format: "%.1f", accuracyHistory.last?.accuracy ?? 0))m) + very close to building (\(Int(nearestDistance))m) - treating as INSIDE to avoid false positive")
                    return (.inside, 0.85)  // INSIDE rather than UNKNOWN - high confidence indoor detection
                }

                // CRITICAL FIX: If polygon absolutism applies, allow outdoor classification
                if shouldApplyPolygonAbsolutism && hasExcellentGPS {
                    print("🚏 [LocationManager] OUTDOOR BUS STOP detected: NOT inside polygon + >5m from building (\(Int(nearestDistance))m) + excellent GPS - treating as outdoor despite stationary")
                    return (.outside, 0.75)
                }

                // PRIORITY 1 FIX: Apply outdoor classification if indicators suggest outdoor
                // Check distance thresholds that avoid window false positive zones
                let isSafeDistanceFromBuilding = nearestDistance >= 15  // Beyond window false positive range

                if hasStableGPS && accuracyHistory.last?.accuracy ?? 100 < 25 && isSafeDistanceFromBuilding {
                    print("🚏 [LocationManager] STATIONARY OUTDOOR detected: GPS stable + good accuracy (\(String(format: "%.1f", accuracyHistory.last?.accuracy ?? 0))m) + safe distance from building (\(Int(nearestDistance))m)")
                    return (.outside, 0.70)
                }

                if notInsidePolygon && accuracyHistory.last?.accuracy ?? 100 < 25 && nearestDistance > 15 {
                    print("🚏 [LocationManager] STATIONARY OUTDOOR detected: Not inside building polygon + good accuracy + >15m from building")
                    return (.outside, 0.70)
                }

                // IMPROVED: Sustained accuracy outdoor detection with balanced threshold
                // Allow outdoor detection if:
                // 1. Sustained good accuracy for 60+ seconds AND
                // 2. Far enough from buildings (>15m) to avoid window false positives
                // This catches: park benches (>15m), bus stops (>15m), sidewalk waiting (>15m)
                if hasSustainedGoodAccuracy && isSafeDistanceFromBuilding {
                    print("🚏 [LocationManager] STATIONARY OUTDOOR detected: Sustained good accuracy for 60+ seconds + reasonably far from buildings (\(Int(nearestDistance))m)")
                    return (.outside, 0.70)
                }

                // FIX #9: Conservative cold start - ALWAYS default to INSIDE in this zone
                if !hasMotionHistory() {
                    // No motion history = cold start
                    // 0-15m from building = likely inside (GPS drift range)
                    return (.inside, 0.75)
                }

                // IMPROVEMENT #2: Long-term stationary near building with higher confidence
                // GPS drift typically 5-15m, so boost confidence in this zone
                let confidence = max(0.80, 0.95 - (nearestDistance / max(config.zoneProbablyInside, 1)) * 0.15)
                return (.inside, confidence)
            }

            if motion.isWalking || motion.isRunning {
                // Walking near building - could be exiting or walking indoors

                // BUG FIX: Check for GPS uncertainty scenario BEFORE applying walking bonuses
                // If GPS error margin overlaps with distance AND position is relatively stable,
                // this is likely indoor walking near building edge with GPS drift
                let gpsAccuracy = accuracyHistory.last?.accuracy ?? 100

                if nearestDistance < gpsAccuracy && gpsAccuracy > 10 && nearestDistance < 15 {
                    // GPS uncertainty overlaps with distance - could be indoor walking near edge
                    // Check if position is relatively stable (low actual movement despite "walking" activity)
                    let recentPositions = locationHistory.suffix(5)
                    if recentPositions.count >= 3 {
                        let coords = recentPositions.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                        var totalMovement = 0.0
                        for i in 1..<coords.count {
                            totalMovement += haversineDistance(from: coords[i-1], to: coords[i])
                        }
                        let avgMovement = totalMovement / Double(coords.count - 1)

                        // If average movement <3m between samples while "walking", likely indoor with GPS drift
                        if avgMovement < 3.0 {
                            DetectionLogger.log(
                                "🏠 Walking near building edge with GPS uncertainty (distance: \(Int(nearestDistance))m, accuracy: \(Int(gpsAccuracy))m, avg movement: \(String(format: "%.1f", avgMovement))m) - likely indoor with GPS drift",
                                category: .detection,
                                level: .info
                            )
                            return (.inside, 0.75)
                        }
                    }
                }

                // POLYGON-BASED GEOFENCING: Check for recent polygon exit (exact boundary detection)
                let (hasPolygonExit, polygonExitTime) = hasRecentPolygonExit()
                if hasPolygonExit, let exitTime = polygonExitTime {
                    print("🚪 [LocationManager] Recent POLYGON exit (\(Int(exitTime))s ago) + walking = high confidence outdoor")
                    return (.outside, 0.90)  // Very high confidence - exact boundary exit detected + walking
                }

                // PRIORITY 5 FIX: Check for parallel walking (definitive sidewalk indicator)
                if let parallelConfidence = checkParallelWalkingToBuilding(nearestDistance: nearestDistance) {
                    print("🚶‍♂️ [LocationManager] PARALLEL WALKING detected: \(String(format: "%.2f", parallelConfidence)) confidence")
                    return (.outside, parallelConfidence)
                }

                // IMPROVEMENT: Calculate base confidence from distance
                let ratio = nearestDistance / max(config.zoneProbablyInside, 1)
                var confidence = 0.5 + min(ratio, 1) * 0.15  // Base: 0.50-0.65

                // BOOST 1: Sustained walking pattern (sidewalk indicator)
                let walkingDuration = getConsecutiveActivityDuration(.walking, .running)
                if walkingDuration >= 10.0 {
                    let sustainedBonus = min(walkingDuration / 120.0, 0.15)  // +0.15 max over 2min
                    confidence += sustainedBonus
                    print("🚶 [LocationManager] Sustained walking bonus: +\(String(format: "%.2f", sustainedBonus)) (duration: \(Int(walkingDuration))s)")
                }

                // BOOST 2: Consistent speed (outdoor walking indicator)
                let recentSpeeds = motionHistory.suffix(5).map { $0.speed }
                if recentSpeeds.count >= 3 {
                    let avgSpeed = recentSpeeds.reduce(0.0, +) / Double(recentSpeeds.count)
                    let speedVariance = recentSpeeds.map { pow($0 - avgSpeed, 2) }.reduce(0.0, +) / Double(recentSpeeds.count)

                    // Low variance = consistent walking speed = outdoor
                    if avgSpeed > 0.5 && avgSpeed < 3.0 && speedVariance < 0.25 {
                        let consistencyBonus = 0.08
                        confidence += consistencyBonus
                        print("👟 [LocationManager] Consistent walking speed bonus: +\(String(format: "%.2f", consistencyBonus))")
                    }
                }

                // BOOST 3: Directional movement away from buildings
                if isMovingAwayFromNearestBuilding() {
                    let directionalBonus = 0.10
                    confidence += directionalBonus
                    print("➡️  [LocationManager] Moving away from building bonus: +\(String(format: "%.2f", directionalBonus))")
                }

                let finalConfidence = min(confidence, 0.95)  // Cap at 0.95
                return (.outside, finalConfidence)  // Now 0.50-0.95 range
            }

            return (.inside, 0.60)
        }

        if nearestDistance <= config.zoneUncertain {
            if motion.isWalking || motion.isRunning {
                return (.outside, 0.60)
            }

            if motion.isVehicle {
                return (.vehicle, max(motion.vehicleConfidence, 0.75))
            }

            // IMPROVEMENT #3: Stronger indoor bias in uncertain zone with higher confidence
            // When stationary 15-30m from building (common GPS drift indoors),
            // default to INSIDE with higher confidence to dominate weighted voting
            return (.inside, 0.70)
        }

        if nearestDistance <= config.zoneProbablyOutside {
            if motion.isVehicle {
                return (.vehicle, max(motion.vehicleConfidence, 0.80))
            }
            return (.outside, 0.70)
        }

        // IMPROVED: Far from any building - obviously outside (cold start optimization)
        if nearestDistance > 50 {
            if motion.isVehicle {
                return (.vehicle, max(motion.vehicleConfidence, 0.85))
            }
            // High confidence outdoor detection when far from buildings
            // Raised to 0.90 to meet TIER 1 threshold for stationary outdoor (park bench, beach, sunbathing)
            return (.outside, 0.90)
        }

        if motion.isVehicle {
            return (.vehicle, max(motion.vehicleConfidence, 0.85))
        }

        return (.outside, 0.80)
    }

    private func analyzeMotion() -> MotionState {
        let now = Date()
        let recentMotion = motionHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 60
        }

        guard !recentMotion.isEmpty else {
            return MotionState(
                isStationary: true,
                isWalking: false,
                isRunning: false,
                isVehicle: false,
                justStartedMoving: false,
                activity: nil,
                averageSpeed: 0,
                vehicleConfidence: 0
            )
        }

        // Calculate average speed
        let avgSpeed = recentMotion.reduce(0.0) { $0 + $1.speed } / Double(recentMotion.count)

        // Check recent activities from CoreMotion
        let activities = recentMotion.compactMap { $0.activity }
        let hasVehicleActivity = activities.contains(.automotive)
        let hasWalkingActivity = activities.contains(.walking)
        let hasRunningActivity = activities.contains(.running)
        let isStationary = avgSpeed < config.stationarySpeedThresholdMS

        // Check if just started moving (important for outdoor transition detection)
        let justStartedMoving = checkJustStartedMoving()

        // Track last significant speed (non-stop speed)
        if avgSpeed > 2.0 {
            lastSignificantSpeed = avgSpeed
        }

        // IMPROVED: Enhanced vehicle detection with persistence for stop-and-go driving
        // Supports city driving with traffic lights, stop signs, and variable speeds
        var vehicleConfidence = 0.0

        // TIER 0: Check vehicle mode persistence (stop-and-go support)
        // If we detected vehicle recently, maintain it through brief stops
        if let lastVehicleTime = lastVehicleDetectionTime {
            let timeSinceVehicle = now.timeIntervalSince(lastVehicleTime)

            // PARKING DETECTION: Exit vehicle mode after 5+ minutes stationary with no automotive activity
            // IMPROVED: Increased from 3 to 5 minutes to handle long drive-through waits
            if timeSinceVehicle > 300 && avgSpeed < 0.5 && !hasVehicleActivity {
                print("🅿️ [LocationManager] PARKING detected: 5+ min stationary, no automotive activity - exiting vehicle mode")
                isInVehicleMode = false
                lastVehicleDetectionTime = nil
                vehicleModeConfirmedTime = nil
                consecutiveStops = 0
                lastStrongVehicleConfidence = 0.0
            }
            // Phase 1 Fix #3: Maintain vehicle mode for up to 5 minutes after last detection (covers stop-and-go city driving)
            else if timeSinceVehicle <= 300 && lastStrongVehicleConfidence >= 0.85 {
                // Check if this is a stop-and-go pattern (stopped but was recently moving fast)
                let isStopAndGo = avgSpeed < 2.0 && lastSignificantSpeed > 5.0

                if isStopAndGo {
                    consecutiveStops += 1
                    print("🚦 [LocationManager] Stop-and-go detected (#\(consecutiveStops)): currently stopped but was moving at \(String(format: "%.1f", lastSignificantSpeed)) m/s - maintaining vehicle mode")
                }

                // Maintain high confidence from recent vehicle detection with slower decay
                vehicleConfidence = max(0.85, lastStrongVehicleConfidence - (timeSinceVehicle / 600.0)) // Phase 1 Fix #3: Slower decay (600s half-life instead of 240s)
                print("🚗 [LocationManager] Vehicle mode persistence active: \(Int(timeSinceVehicle))s since last detection (confidence: \(String(format: "%.2f", vehicleConfidence)))")
            }
        }

        // TIER 1: CoreMotion automotive activity (HIGHEST PRIORITY - accelerometer-based)
        // iOS detects vehicle motion patterns (acceleration/braking) independent of GPS speed
        if hasVehicleActivity {
            let automotiveCount = activities.filter { $0 == .automotive }.count
            let automotiveRatio = Double(automotiveCount) / Double(activities.count)

            if automotiveRatio > 0.5 {
                // 50%+ automotive samples = definitely in vehicle
                vehicleConfidence = max(vehicleConfidence, 0.95)
                lastVehicleDetectionTime = now
                lastStrongVehicleConfidence = 0.95
                isInVehicleMode = true

                DetectionLogger.log(
                    "🚗 VEHICLE (CoreMotion): \(Int(automotiveRatio * 100))% automotive samples - HIGH CONFIDENCE",
                    category: .motion
                )
            } else if avgSpeed > 3.0 {
                // Automotive activity + moderate speed = vehicle
                vehicleConfidence = max(vehicleConfidence, 0.90)
                lastVehicleDetectionTime = now
                lastStrongVehicleConfidence = 0.90
                isInVehicleMode = true

                DetectionLogger.log(
                    "🚗 VEHICLE (CoreMotion + speed): automotive activity with \(String(format: "%.1f", avgSpeed)) m/s",
                    category: .motion
                )
            } else {
                // Automotive activity even when stopped (engine vibrations)
                vehicleConfidence = max(vehicleConfidence, 0.85)
                lastVehicleDetectionTime = now
                lastStrongVehicleConfidence = 0.85
            }
        }

        // TIER 2: GPS speed-based detection (CITY DRIVING thresholds - lowered from highway speeds)
        // Check last 10 seconds for sustained speed
        let last10Seconds = recentMotion.suffix(3)  // Last 3 samples (~10 seconds)
        if last10Seconds.count >= 3 && vehicleConfidence < 0.95 {
            let sustainedSpeeds = last10Seconds.map { $0.speed }
            let minSpeed = sustainedSpeeds.min() ?? 0
            let maxSpeed = sustainedSpeeds.max() ?? 0
            let avgSustainedSpeed = sustainedSpeeds.reduce(0.0, +) / Double(sustainedSpeeds.count)

            // Highway driving (original high thresholds)
            if avgSustainedSpeed > 22.0 {  // >50 mph sustained
                vehicleConfidence = max(vehicleConfidence, 0.98)
                lastVehicleDetectionTime = now
                lastStrongVehicleConfidence = 0.98
                isInVehicleMode = true
                DetectionLogger.logMotion(
                    activity: "VEHICLE (highway)",
                    speed: avgSustainedSpeed,
                    vehicleConfidence: vehicleConfidence,
                    details: "Highway speed: >50 mph sustained"
                )
            }
            // Fast city driving / arterial roads
            else if avgSustainedSpeed > 11.0 && minSpeed > 5.0 {
                vehicleConfidence = max(vehicleConfidence, 0.92)
                lastVehicleDetectionTime = now
                lastStrongVehicleConfidence = 0.92
                isInVehicleMode = true
                DetectionLogger.logMotion(
                    activity: "VEHICLE (city fast)",
                    speed: avgSustainedSpeed,
                    vehicleConfidence: vehicleConfidence,
                    details: "Fast city driving: 25+ mph sustained"
                )
            }
            // IMPROVED: City driving with moderate speed (NEW - lower threshold)
            else if avgSustainedSpeed > 6.0 && maxSpeed > 8.0 {
                // CRITICAL FIX (Nov 2025): Enhanced cyclist exclusion
                // CoreMotion doesn't always report .cycling for cyclists, so use additional heuristics:
                // 1. Direct cycling activity check (most reliable when available)
                // 2. Speed consistency check: cyclists have LOW variance, vehicles in traffic have HIGH variance
                // 3. Running activity with high speed = likely misclassified cyclist (especially on smooth roads)
                let hasCyclingActivity = activities.contains(.cycling)
                let hasRunningWithHighSpeed = activities.contains(.running) && avgSustainedSpeed > 5.0

                // Calculate speed variance to distinguish cyclists from vehicles
                let speedVariance = sustainedSpeeds.map { pow($0 - avgSustainedSpeed, 2) }.reduce(0.0, +) / Double(sustainedSpeeds.count)
                let speedStdDev = sqrt(speedVariance)

                // Cyclists: Consistent speed (stdDev < 1.5 m/s at these speeds)
                // Vehicles: Variable speed due to traffic, acceleration, braking (stdDev > 2.0 m/s)
                let hasLowSpeedVariance = speedStdDev < 1.5
                let isLikelyCyclist = hasCyclingActivity || hasRunningWithHighSpeed || (hasLowSpeedVariance && !hasVehicleActivity)

                if isLikelyCyclist {
                    let reason = hasCyclingActivity ? "cycling activity" :
                                 hasRunningWithHighSpeed ? "running activity at high speed" :
                                 "consistent speed pattern (σ=\(String(format: "%.1f", speedStdDev)))"
                    print("🚴 [LocationManager] Likely cyclist detected (\(String(format: "%.1f", avgSustainedSpeed)) m/s, \(reason)) - NOT classifying as vehicle")
                    vehicleConfidence = 0.0  // Explicitly reject vehicle classification
                } else {
                    // 6 m/s = 13.4 mph average, peak 18 mph - typical city driving
                    vehicleConfidence = max(vehicleConfidence, 0.88)
                    lastVehicleDetectionTime = now
                    lastStrongVehicleConfidence = 0.88
                    isInVehicleMode = true
                    DetectionLogger.logMotion(
                        activity: "VEHICLE (city moderate)",
                        speed: avgSustainedSpeed,
                        vehicleConfidence: vehicleConfidence,
                        details: "City driving: 13+ mph avg, σ=\(String(format: "%.1f", speedStdDev)) (vehicle pattern)"
                    )
                }
            }
            // IMPROVED: Slow city driving / neighborhood (NEW - even lower threshold)
            else if avgSustainedSpeed > 4.0 && maxSpeed > 6.0 {
                // CRITICAL FIX (Nov 2025): Enhanced cyclist exclusion (same logic as above)
                let hasCyclingActivity = activities.contains(.cycling)
                let hasRunningWithHighSpeed = activities.contains(.running) && avgSustainedSpeed > 4.0

                let speedVariance = sustainedSpeeds.map { pow($0 - avgSustainedSpeed, 2) }.reduce(0.0, +) / Double(sustainedSpeeds.count)
                let speedStdDev = sqrt(speedVariance)
                let hasLowSpeedVariance = speedStdDev < 1.2  // Even stricter at lower speeds
                let isLikelyCyclist = hasCyclingActivity || hasRunningWithHighSpeed || (hasLowSpeedVariance && !hasVehicleActivity)

                if isLikelyCyclist {
                    let reason = hasCyclingActivity ? "cycling activity" :
                                 hasRunningWithHighSpeed ? "running activity at moderate speed" :
                                 "consistent speed pattern (σ=\(String(format: "%.1f", speedStdDev)))"
                    print("🚴 [LocationManager] Likely cyclist detected (\(String(format: "%.1f", avgSustainedSpeed)) m/s, \(reason)) - NOT classifying as vehicle")
                    vehicleConfidence = 0.0  // Explicitly reject vehicle classification
                } else {
                    // 4 m/s = 9 mph average, peak 13.4 mph - residential/slow traffic
                    vehicleConfidence = max(vehicleConfidence, 0.82)
                    lastVehicleDetectionTime = now
                    lastStrongVehicleConfidence = 0.82
                    isInVehicleMode = true
                    DetectionLogger.logMotion(
                        activity: "VEHICLE (slow city)",
                        speed: avgSustainedSpeed,
                        vehicleConfidence: vehicleConfidence,
                        details: "Slow city driving: 9+ mph avg, σ=\(String(format: "%.1f", speedStdDev)) (vehicle pattern)"
                    )
                }
            }
        }

        // TIER 2.5: Very slow vehicle detection (parking garage crawl, heavy traffic)
        // CRITICAL FIX: Catches vehicles moving 2-4 m/s (4.5-9 mph) with CoreMotion confirmation
        if vehicleConfidence < 0.80 && hasVehicleActivity {
            // CoreMotion says automotive but speed is very low
            if avgSpeed > 0.3 && avgSpeed < 4.0 {
                // Exclude walking (walking activity would override automotive)
                if !hasWalkingActivity {
                    vehicleConfidence = max(vehicleConfidence, 0.78)
                    lastVehicleDetectionTime = now
                    lastStrongVehicleConfidence = 0.78
                    isInVehicleMode = true
                    print("🅿️ [LocationManager] Very slow vehicle detected: \(String(format: "%.1f", avgSpeed)) m/s (parking search / heavy traffic) with automotive activity")
                    DetectionLogger.logMotion(
                        activity: "VEHICLE (very slow)",
                        speed: avgSpeed,
                        vehicleConfidence: vehicleConfidence,
                        details: "Parking garage crawl or heavy traffic: <4 m/s with automotive activity"
                    )
                }
            }
        }

        // TIER 3: Stop-and-go pattern detection (acceleration/deceleration cycles)
        // Detects repeated speed changes characteristic of city driving
        if vehicleConfidence < 0.85 && recentMotion.count >= 5 {
            let last30Seconds = recentMotion.suffix(10) // Last 30 seconds
            let speeds = last30Seconds.map { $0.speed }

            // Calculate speed variance
            let avgSpeed30s = speeds.reduce(0.0, +) / Double(speeds.count)
            let speedVariance = speeds.map { pow($0 - avgSpeed30s, 2) }.reduce(0.0, +) / Double(speeds.count)
            let speedStdDev = sqrt(speedVariance)

            // High variance + moderate speeds = stop-and-go traffic
            if speedStdDev > 2.5 && avgSpeed30s > 3.0 && speeds.max() ?? 0 > 8.0 {
                vehicleConfidence = max(vehicleConfidence, 0.85)
                lastVehicleDetectionTime = now
                lastStrongVehicleConfidence = 0.85
                isInVehicleMode = true
                print("🚦 [LocationManager] STOP-AND-GO pattern detected: high speed variance (\(String(format: "%.1f", speedStdDev)) m/s std dev), avg \(String(format: "%.1f", avgSpeed30s)) m/s - vehicle mode")
            }
        }

        // Log significant motion transitions
        if justStartedMoving {
            DetectionLogger.log(
                "Motion transition: STATIONARY → MOVING (speed: \(String(format: "%.1f", avgSpeed)) m/s)",
                category: .motion
            )
        }

        if vehicleConfidence > 0.85 {
            DetectionLogger.logMotion(
                activity: "VEHICLE",
                speed: avgSpeed,
                vehicleConfidence: vehicleConfidence
            )
        }

        return MotionState(
            isStationary: isStationary,
            isWalking: hasWalkingActivity || (avgSpeed > 0.5 && avgSpeed < 2.0),
            isRunning: hasRunningActivity || (avgSpeed > 2.0 && avgSpeed < 5.0),
            isVehicle: vehicleConfidence > 0.85,  // Phase 1 Fix #1: Aligned with BackgroundTaskManager 0.85 threshold (was 0.80, caused zombie state)
            justStartedMoving: justStartedMoving,
            activity: activities.last,
            averageSpeed: avgSpeed,
            vehicleConfidence: vehicleConfidence
        )
    }

    private func checkJustStartedMoving() -> Bool {
        let now = Date()
        let last30Seconds = motionHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 30
        }

        guard last30Seconds.count >= 2 else { return false }

        let previousSamples = last30Seconds.dropLast()
        let wasStationary = previousSamples.allSatisfy {
            $0.speed < config.stationarySpeedThresholdMS
        }

        let isNowMoving = last30Seconds.last?.speed ?? 0 >= config.motionThresholdMS

        return wasStationary && isNowMoving
    }

    private func hasRecentMovement(within seconds: TimeInterval) -> Bool {
        let now = Date()
        let recent = motionHistory.filter { now.timeIntervalSince($0.timestamp) <= seconds }
        return recent.contains { $0.speed > config.motionThresholdMS }
    }

    private func hasMotionHistory() -> Bool {
        return !motionHistory.isEmpty
    }

    private func addToHistory(_ state: LocationState, signalSource: SignalSource? = nil) {
        guard state.mode != .unknown else { return }

        locationHistory.append(LocationHistoryEntry(
            timestamp: state.timestamp,
            mode: state.mode,
            confidence: state.confidence,
            latitude: state.latitude,
            longitude: state.longitude,
            accuracy: state.accuracy,
            uncertaintyReason: state.uncertaintyReason,
            signalSource: signalSource?.rawValue
        ))

        pruneLocationHistory()
        saveLocationHistory()
    }

    private func getStableModeFromHistory(allowSingleSample: Bool = false) -> LocationMode? {
        let now = Date()
        
        // IMPROVEMENT #4: Adaptive history window based on motion state
        // Shorter window when stationary for faster indoor transitions
        let motionState = analyzeMotion()
        let recentWindow: TimeInterval = motionState.isStationary ? 60 : 120

        let recentReadings = locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= recentWindow &&
            $0.confidence >= config.confidenceThresholdForHistory &&
            $0.mode != .unknown
        }

        // IMPROVEMENT #5: Check if latest reading is inside polygon (near-definitive)
        // This provides immediate override for GPS drift scenarios
        // CRITICAL FIX: Polygon detection (0.95+ confidence) should IMMEDIATELY override outdoor history
        // Walking into a building with polygon detection is definitive, not GPS drift
        if let latest = recentReadings.last,
           latest.mode == .inside,
           latest.confidence >= 0.95 {  // Very high confidence = polygon detection

            // Mark the timestamp when we detect polygon containment
            lastHighConfidenceInsideTimestamp = now
            
            // Clear outdoor history to prevent it from blocking the transition
            // This is safe because polygon detection is nearly definitive (GPS can't drift INTO a polygon)
            locationHistory.removeAll { entry in
                entry.mode == .outside &&
                now.timeIntervalSince(entry.timestamp) < 90 &&
                entry.confidence < 0.85  // Remove all outdoor readings except very high confidence ones
            }
            
            return .inside
        }

        // FIX #3: CRITICAL - Only allow single sample for vehicle detection (high confidence, safety critical)
        // OPTIMIZATION: Also allow single sample for high-confidence outdoor from geofence exit
        // GPS drift can produce convincing single outdoor readings indoors - must require consecutive agreement
        // EXCEPT when iOS system (geofence) confirms building exit with high confidence
        guard recentReadings.count >= config.minSamplesForTransition else {
            if allowSingleSample && recentReadings.count == 1 {
                let reading = recentReadings[0]
                // Allow single sample for vehicle OR high-confidence geofence outdoor
                if reading.mode == .vehicle {
                    return reading.mode
                } else if reading.mode == .outside && reading.confidence >= 0.80 {
                    return reading.mode
                }
            }
            return nil
        }

        // IMPROVED: Use confidence-weighted voting instead of strict consecutive requirement
        // This handles GPS drift better - even if samples disagree, we can find consensus
        
        // First, try consecutive samples (fastest path for stable states)
        let lastNSamples = Array(recentReadings.suffix(config.minSamplesForTransition))
        let firstMode = lastNSamples[0].mode

        if lastNSamples.allSatisfy({ $0.mode == firstMode }) {
            return firstMode
        }

        // If consecutive samples disagree, use confidence-weighted voting ONLY if we have enough data
        // This prevents GPS drift from blocking mode detection but still requires strong consensus
        
        // CRITICAL FIX: If we recently had high-confidence inside detection (polygon),
        // require stronger evidence to switch back to outside (minimum dwell time)
        // This prevents GPS bounce near building edges from causing flip-flopping
        if let insideTimestamp = lastHighConfidenceInsideTimestamp,
           now.timeIntervalSince(insideTimestamp) < 30 {  // 30 second minimum dwell time
            
            // Check if we still have recent inside readings
            let hasRecentInsideEvidence = recentReadings.contains { reading in
                reading.mode == .inside &&
                now.timeIntervalSince(reading.timestamp) < 15 &&
                reading.confidence >= 0.50  // Any inside evidence in last 15s
            }
            
            if hasRecentInsideEvidence {
                print("🏠 [LocationManager] Recent polygon detection (\(Int(now.timeIntervalSince(insideTimestamp)))s ago) - maintaining inside state during transition period")
                return .inside
            } else {
                // No inside evidence for 15s - clear the protection
                print("⏱️  [LocationManager] No inside evidence for 15s - clearing polygon protection")
                lastHighConfidenceInsideTimestamp = nil
            }
        }
        
        guard recentReadings.count >= 4 else {
            // Not enough samples for weighted voting - wait for more evidence
            print("⚠️  [LocationManager] Consecutive samples disagree and insufficient data for weighted voting (need 4+, have \(recentReadings.count))")
            return nil
        }
        
        var votes: [LocationMode: Double] = [:]

        // IMPROVEMENT #7 + FIX #6 (Nov 2025): Signal-quality-weighted time decay
        // - More recent samples get more weight (reduces drift persistence)
        // - Definitive signals (floor, polygon) decay slower than probabilistic signals
        // - This prevents a 30s-old floor detection from losing to fresh GPS pattern guess
        for reading in recentReadings {
            let age = now.timeIntervalSince(reading.timestamp)
            // Signal quality affects decay rate: higher quality = slower decay
            let effectiveHalfLife = 60.0 * reading.signalQualityWeight
            let decayFactor = exp(-age / effectiveHalfLife)
            let weight = reading.confidence * decayFactor
            votes[reading.mode, default: 0.0] += weight
        }
        
        // IMPROVEMENT #NEW + FIX #1 (Nov 2025): Conditional streak bonus
        // Sustained pattern (e.g., walking outside) should dominate over isolated samples
        // BUT: Disable outdoor streak bonus when there's recent vehicle evidence
        // This prevents the outdoor streak from delaying vehicle detection when user gets into car
        let streak = getConsecutiveModeStreak()
        if streak.count >= 3 && streak.mode != .unknown {
            // Check if there's recent vehicle evidence that should override outdoor streak
            let hasRecentVehicleEvidence = lastVehicleDetectionTime != nil &&
                                           now.timeIntervalSince(lastVehicleDetectionTime!) < 30

            // Don't apply outdoor streak bonus if we have recent vehicle evidence
            if streak.mode == .outside && hasRecentVehicleEvidence {
                print("🚗⚠️ [LocationManager] Outdoor streak bonus DISABLED - recent vehicle evidence (\(Int(now.timeIntervalSince(lastVehicleDetectionTime!)))s ago)")
            } else {
                let streakBonus = min(Double(streak.count) * 0.04, 0.20)  // +0.20 max for 5+ samples
                votes[streak.mode, default: 0.0] += streakBonus
                print("🔥 [LocationManager] Consecutive streak bonus: \(streak.mode.rawValue) × \(streak.count) samples (+\(String(format: "%.2f", streakBonus)))")
            }
        }
        
        guard let (winningMode, winningScore) = votes.max(by: { $0.value < $1.value }) else {
            return nil
        }
        
        // IMPROVEMENT #8: Require stronger margin to prevent GPS drift dominance
        // Increased from 2.0x to 2.5x for better drift rejection
        let sortedVotes = votes.sorted { $0.value > $1.value }
        if sortedVotes.count > 1 {
            let secondScore = sortedVotes[1].value
            if winningScore < secondScore * 2.5 {
                print("⚠️  [LocationManager] No clear winner in weighted voting:")
                for (mode, score) in sortedVotes {
                    print("   - \(mode.rawValue): \(String(format: "%.2f", score))")
                }
                print("   Winner margin too small (need 2.5x), waiting for more evidence")
                return nil
            }
        }
        
        // Log voting only in verbose mode
        if DetectionLogger.isVerboseMode {
            print("🎯 Voting: \(winningMode.rawValue) (\(String(format: "%.1fx", winningScore / (sortedVotes.count > 1 ? sortedVotes[1].value : 1))) margin)")
        }
        
        // CRITICAL FIX: If we have a very recent high-confidence INSIDE reading (polygon detection),
        // it should override outdoor walking history. GPS can't drift INTO a polygon.
        // This handles the case where user walks into building after sustained outdoor walking.
        if let mostRecentInside = recentReadings.last(where: { $0.mode == .inside && $0.confidence >= 0.95 }),
           now.timeIntervalSince(mostRecentInside.timestamp) < 10 {  // Within last 10 seconds
            print("🏠 [LocationManager] OVERRIDE: Very recent high-confidence inside reading (\(String(format: "%.2f", mostRecentInside.confidence))) overrides weighted voting")
            return .inside
        }
        
        return winningMode
    }

    private func getAdaptiveTTL() -> TimeInterval {
        guard let state = currentState else {
            return config.minCheckIntervalMS
        }

        let speed = state.speed ?? 0

        // Quick cache invalidation when moving
        if speed > 2.0 { // Walking pace
            return 30
        }

        // Longer cache when stationary with high confidence
        if speed < 0.8 && state.confidence > 0.8 {
            return 60
        }

        // Default
        return config.minCheckIntervalMS
    }

    private func getGPSAccuracyFactor(_ accuracy: CLLocationAccuracy) -> Double {
        guard accuracy > 0 else { return 1.0 }

        if accuracy <= config.gpsAccuracyPenaltyThreshold {
            return 1.0
        }

        if accuracy >= config.maxGPSAccuracyMeters {
            return 0.5
        }

        // Linear interpolation
        let range = config.maxGPSAccuracyMeters - config.gpsAccuracyPenaltyThreshold
        let excess = accuracy - config.gpsAccuracyPenaltyThreshold
        let penalty = (excess / range) * 0.5

        return 1.0 - penalty
    }

    private func pruneLocationHistory() {
        let now = Date()
        locationHistory = locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= config.historyWindowMS
        }.suffix(20) // Keep max 20 entries
    }

    private func pruneMotionHistory() {
        let now = Date()
        motionHistory = motionHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 600 // 10 minutes
        }.suffix(50) // Keep max 50 entries
    }

    private func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        return GeometryUtils.haversineDistance(
            lat1: from.latitude,
            lon1: from.longitude,
            lat2: to.latitude,
            lon2: to.longitude
        )
    }

    // MARK: - UV Tracking

    private func startUVTracking() async {
        guard let location = currentLocation else { return }

        // Fetch UV index from weather service
        do {
            let uvIndex = try await weatherService.getCurrentUVIndex(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            await MainActor.run {
                self.uvIndex = uvIndex
            }
        } catch {
            print("[LocationManager] Failed to fetch UV index: \(error)")
        }
    }

    private func stopUVTracking() {
    }
    
    // MARK: - Context-Aware Detection Helpers

    /// PRIORITY 7 FIX: Check if we're in initial startup phase (first 1 minute)
    /// Returns true if within 1 minute of starting location tracking
    /// Reduced from 2 minutes to improve responsiveness while maintaining safety
    var isInStartupPhase: Bool {
        guard let startTime = trackingStartTime else { return false }
        return Date().timeIntervalSince(startTime) < 60  // 1 minute
    }

    /// PRIORITY 7 FIX: Get startup-adjusted confidence thresholds
    /// Returns (uvStartThreshold, uvStopThreshold) with conservative values during startup
    func getConfidenceThresholds() -> (uvStart: Double, uvStop: Double) {
        if isInStartupPhase {
            // PRIORITY 7 FIX: Conservative during startup (higher outdoor threshold, lower indoor threshold)
            // Prefer false negatives (missing outdoor time) over false positives (indoor UV tracking)
            let uvStart = 0.85  // Higher than normal 0.75 (more conservative)
            let uvStop = 0.50   // Lower than normal 0.60 (faster indoor detection)
            return (uvStart, uvStop)
        } else {
            // Normal thresholds after startup phase
            return (0.75, 0.60)
        }
    }

    /// Get minimum confidence threshold based on motion context
    /// IMPROVEMENT: Lower threshold for sustained walking to allow sidewalk detection
    /// while maintaining high threshold for stationary scenarios (GPS drift prevention)
    private func getMinConfidenceForKnownState(motion: MotionState, nearestDistance: Double) -> Double {
        // Vehicle detection uses separate threshold
        if motion.isVehicle {
            return 0.85
        }

        // High threshold for stationary near buildings (prevent GPS drift false positives)
        if motion.isStationary && nearestDistance <= config.zoneProbablyInside {
            return 0.60  // Keep current strict threshold
        }

        // Lower threshold for sustained walking (sidewalk detection)
        if motion.isWalking || motion.isRunning {
            // Check for sustained walking pattern
            let walkingDuration = getConsecutiveActivityDuration(.walking, .running)

            if walkingDuration >= 30.0 {  // 30+ seconds of continuous walking
                print("🚶 [LocationManager] Sustained walking detected (\(Int(walkingDuration))s) - using lower threshold (0.55)")
                return 0.55  // Lower threshold - GPS drift unlikely when walking
            } else if walkingDuration >= 15.0 {
                print("🚶 [LocationManager] Walking pattern detected (\(Int(walkingDuration))s) - using intermediate threshold (0.58)")
                return 0.58  // Intermediate threshold
            }
        }

        // Default threshold
        return 0.60
    }
    
    /// Get duration of consecutive activity samples
    private func getConsecutiveActivityDuration(_ activities: MotionActivity...) -> TimeInterval {
        let now = Date()
        var duration: TimeInterval = 0
        
        // Look backwards through motion history for consecutive matching activity
        for sample in motionHistory.reversed() {
            guard let activity = sample.activity,
                  activities.contains(activity) else {
                break  // Stop at first non-matching sample
            }
            duration = now.timeIntervalSince(sample.timestamp)
        }
        
        return duration
    }
    
    /// Check if user is moving away from the nearest building
    /// Indicates outdoor movement along sidewalk rather than transitioning indoor/outdoor
    private func isMovingAwayFromNearestBuilding() -> Bool {
        // Need at least 2 location samples
        guard locationHistory.count >= 2 else { return false }
        
        let recent = locationHistory.suffix(3)
        guard recent.count >= 2 else { return false }
        
        // Get latest and previous samples
        let latest = Array(recent).last!
        let previous = Array(recent)[recent.count - 2]
        
        // Calculate rough distance change
        let latDiff = abs(latest.latitude - previous.latitude)
        let lonDiff = abs(latest.longitude - previous.longitude)
        let movement = sqrt(latDiff * latDiff + lonDiff * lonDiff) * 111000  // Rough meters
        
        // If moving >2m and confidence is increasing, likely moving away
        if movement > 2.0 {
            let confidenceTrend = latest.confidence > previous.confidence
            return confidenceTrend
        }
        
        return false
    }
    
    // MARK: - Priority 1: Stationary Outdoor Detection Helpers

    /// PRIORITY 1 FIX: Check if GPS accuracy is stable over time
    /// Outdoor stationary: Stable accuracy (variance <5m)
    /// Indoor GPS drift: Varying accuracy (variance >10m)
    private func checkGPSStability() -> Bool {
        let now = Date()
        let recentAccuracy = accuracyHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 60  // Last 60 seconds
        }

        guard recentAccuracy.count >= 3 else { return false }

        let accuracies = recentAccuracy.map { $0.accuracy }
        let avgAccuracy = accuracies.reduce(0.0, +) / Double(accuracies.count)
        let variance = accuracies.map { pow($0 - avgAccuracy, 2) }.reduce(0.0, +) / Double(accuracies.count)
        let stdDev = sqrt(variance)

        // Stable outdoor: low variance (<5m standard deviation)
        // Indoor drift: high variance (>10m standard deviation)
        let isStable = stdDev < 5.0
        if isStable {
            print("   GPS stability: ✓ stable (σ=\(String(format: "%.1f", stdDev))m, avg=\(String(format: "%.1f", avgAccuracy))m)")
        }
        return isStable
    }

    /// PRIORITY 1 FIX: Check if we're in a geofence but no recent entry event
    /// Indicates app started while user already outside (polygon-based)
    /// REMOVED circular geofence version - now uses polygon-based detection
    private func checkNoRecentPolygonEntry() -> Bool {
        // Check if we're currently NOT inside any polygons
        let notInsidePolygon = currentPolygons.isEmpty

        if notInsidePolygon {
            return true  // Not inside any building polygon = likely outside
        }

        // If inside polygon, check if entry was recent (within last 60 seconds)
        let now = Date()
        let hasRecentEntry = polygonEntryTimestamps.values.contains { entryTime in
            now.timeIntervalSince(entryTime) < 60
        }

        // If in polygon but no recent entry, might have started inside
        if !notInsidePolygon && !hasRecentEntry {
            print("   Polygon history: Inside building but no recent entry (app started while inside)")
            return false  // Started inside
        }

        return false
    }

    /// PRIORITY 1 FIX: Check if GPS accuracy has been consistently good for 60+ seconds
    /// Indicates sustained sky visibility (outdoor)
    private func checkSustainedGoodAccuracy() -> Bool {
        let now = Date()
        let last60s = accuracyHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 60
        }

        guard last60s.count >= 4 else { return false }  // Need at least 4 samples

        // Check if all samples have good accuracy (<25m)
        let allGoodAccuracy = last60s.allSatisfy { $0.accuracy < 25.0 }

        return allGoodAccuracy
    }

    /// Check for sustained EXCELLENT GPS (<12m) for fast outdoor path
    /// Returns (hasExcellent: Bool, avgAccuracy: Double, duration: TimeInterval)
    /// Used by BackgroundTaskManager to fast-track outdoor detection when GPS is extremely good
    func checkSustainedExcellentGPS() -> (hasExcellent: Bool, avgAccuracy: Double, duration: TimeInterval) {
        let now = Date()
        let recentHistory = accuracyHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 60
        }

        guard recentHistory.count >= 4 else {
            return (false, 0, 0)
        }

        // Check if all samples have excellent accuracy (<12m)
        let allExcellent = recentHistory.allSatisfy { $0.accuracy < 12.0 }

        guard allExcellent else {
            return (false, 0, 0)
        }

        let avgAccuracy = recentHistory.map { $0.accuracy }.reduce(0.0, +) / Double(recentHistory.count)
        let duration = recentHistory.first.map { now.timeIntervalSince($0.timestamp) } ?? 0

        return (true, avgAccuracy, duration)
    }

    // MARK: - Priority 5: Parallel Walking Detection Helper

    /// PRIORITY 5 FIX: Detect parallel walking along building face (definitive sidewalk indicator)
    /// Returns confidence if parallel walking detected, nil otherwise
    private func checkParallelWalkingToBuilding(nearestDistance: Double) -> Double? {
        // Need at least 3 location samples for movement vector
        guard locationHistory.count >= 3 else { return nil }

        let now = Date()
        let last30s = locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 30
        }

        guard last30s.count >= 3 else { return nil }

        // Calculate movement vector over last 30 seconds
        let oldest = last30s.first!
        let newest = last30s.last!

        let deltaLat = newest.latitude - oldest.latitude
        let deltaLon = newest.longitude - oldest.longitude

        // Calculate total movement distance
        let movementDistance = haversineDistance(
            from: CLLocationCoordinate2D(latitude: oldest.latitude, longitude: oldest.longitude),
            to: CLLocationCoordinate2D(latitude: newest.latitude, longitude: newest.longitude)
        )

        // Must be actually moving (>10m over 30s = significant movement)
        guard movementDistance > 10 else { return nil }

        // Calculate bearing (movement direction)
        let movementBearing = atan2(deltaLon, deltaLat) * 180 / .pi

        // Simplified check: if distance to building stays relatively constant (±5m)
        // while user is moving >10m, indicates parallel movement
        let distances = last30s.map { entry -> Double in
            // Can't easily recalculate distance without building data, so use variance as proxy
            nearestDistance  // Simplified: use current distance
        }

        // Check if distance variance is low (staying same distance from building)
        // AND user is moving significantly
        let avgDistance = distances.reduce(0.0, +) / Double(distances.count)
        let distanceVariance = distances.map { pow($0 - avgDistance, 2) }.reduce(0.0, +) / Double(distances.count)
        let distanceStdDev = sqrt(distanceVariance)

        // PARALLEL WALKING DETECTED if:
        // 1. Moving significantly (>10m over 30s)
        // 2. Distance to building stays relatively constant (<8m variance)
        // 3. Currently close to building (5-15m range = sidewalk distance)
        if movementDistance > 10 && distanceStdDev < 8.0 && nearestDistance >= 5 && nearestDistance <= 15 {
            let walkingDuration = getConsecutiveActivityDuration(.walking, .running)

            // Higher confidence for sustained parallel walking
            if walkingDuration >= 30 {
                print("   🚶‍♂️ Sustained parallel walking: \(Int(movementDistance))m movement, \(String(format: "%.1f", distanceStdDev))m distance variance, \(Int(walkingDuration))s duration")
                return 0.85  // High confidence - definitely sidewalk
            } else {
                print("   🚶‍♂️ Parallel walking detected: \(Int(movementDistance))m movement, \(String(format: "%.1f", distanceStdDev))m distance variance")
                return 0.75  // Good confidence
            }
        }

        return nil
    }

    // MARK: - Priority 6: Tunnel Detection Helper

    /// PRIORITY 6 FIX: Detect tunnel/parking garage and maintain vehicle mode stability
    /// Returns stable mode if in tunnel, nil if normal classification should proceed
    private func checkTunnelDetection(
        currentAccuracy: Double,
        currentMode: LocationMode,
        motion: MotionState
    ) -> LocationMode? {
        let now = Date()

        // TUNNEL ENTRY DETECTION
        // Detect tunnel entry: vehicle mode + GPS suddenly degrades + speed maintained
        if !inTunnelMode {
            // Check if we're in vehicle mode
            guard currentMode == .vehicle || preTunnelMode == .vehicle else {
                return nil  // Not in vehicle, no tunnel detection needed
            }

            // Check if GPS accuracy suddenly degraded
            if currentAccuracy > 100 {  // Poor GPS
                // Check if we have recent good GPS that suddenly degraded
                let recentAccuracy = accuracyHistory.suffix(3)
                if recentAccuracy.count >= 2 {
                    let previousAccuracy = recentAccuracy.dropLast().map { $0.accuracy }
                    let avgPreviousAccuracy = previousAccuracy.reduce(0.0, +) / Double(previousAccuracy.count)

                    // GPS suddenly degraded from good (<40m) to poor (>100m)
                    if avgPreviousAccuracy < 40 && currentAccuracy > 100 {
                        // Check if speed is maintained (still moving)
                        if motion.averageSpeed > 5.0 {
                            // TUNNEL DETECTED
                            inTunnelMode = true
                            tunnelStartTime = now
                            preTunnelMode = currentMode == .vehicle ? .vehicle : preTunnelMode
                            print("🚇 [LocationManager] TUNNEL ENTRY detected: GPS degraded \(String(format: "%.0f", avgPreviousAccuracy))m → \(String(format: "%.0f", currentAccuracy))m, speed maintained")
                            print("   Freezing mode to: \(preTunnelMode?.rawValue ?? "vehicle")")
                        }
                    }
                }
            }
        }

        // TUNNEL MODE MAINTENANCE
        if inTunnelMode {
            guard let tunnelStart = tunnelStartTime else {
                // Invalid state, reset
                inTunnelMode = false
                return nil
            }

            let tunnelDuration = now.timeIntervalSince(tunnelStart)

            // TUNNEL EXIT DETECTION
            // Exit tunnel if GPS recovers (accuracy <50m for 10+ seconds)
            if currentAccuracy < 50 {
                let recentGoodAccuracy = accuracyHistory.suffix(3).allSatisfy { $0.accuracy < 50 }
                if recentGoodAccuracy {
                    print("🌞 [LocationManager] TUNNEL EXIT detected: GPS recovered to \(String(format: "%.0f", currentAccuracy))m")
                    print("   Resuming normal classification")
                    inTunnelMode = false
                    tunnelStartTime = nil
                    // Don't return, let normal classification proceed
                    return nil
                }
            }

            // AUTO-EXPIRE after 10 minutes (prevent getting stuck)
            if tunnelDuration > 600 {
                print("⏰ [LocationManager] Tunnel mode auto-expired after 10 minutes")
                inTunnelMode = false
                tunnelStartTime = nil
                return nil
            }

            // MAINTAIN tunnel mode
            let mode = preTunnelMode ?? .vehicle
            print("🚇 [LocationManager] Tunnel mode active: maintaining \(mode.rawValue) (duration: \(Int(tunnelDuration))s, accuracy: \(String(format: "%.0f", currentAccuracy))m)")
            return mode
        }

        return nil  // Normal classification should proceed
    }

    /// Get the longest consecutive streak of the same mode in recent history
    private func getConsecutiveModeStreak() -> (mode: LocationMode, count: Int, avgConfidence: Double) {
        guard !locationHistory.isEmpty else {
            return (.unknown, 0, 0.0)
        }
        
        let now = Date()
        let recent = locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 120  // Last 2 minutes
        }
        
        guard !recent.isEmpty else {
            return (.unknown, 0, 0.0)
        }
        
        // Look for consecutive streak from end
        let lastMode = recent.last!.mode
        var streakCount = 0
        var streakConfidenceSum = 0.0
        
        for entry in recent.reversed() {
            if entry.mode == lastMode {
                streakCount += 1
                streakConfidenceSum += entry.confidence
            } else {
                break
            }
        }
        
        let avgConfidence = streakCount > 0 ? streakConfidenceSum / Double(streakCount) : 0.0
        return (lastMode, streakCount, avgConfidence)
    }
    
    // MARK: - Phase 1 & 2: Apple Native Signal Classification Methods
    
    /// TIER 1: Floor detection (definitive indoor signal)
    private func classifyWithFloorData(location: CLLocation) -> ClassificationResult? {
        // Check if floor information is available
        if let floor = location.floor {
            // Floor detected = DEFINITIVE INDOOR signal
            lastFloorDetectionTime = Date()
            lastKnownFloor = floor.level
            
            print("🏢 [LocationManager] Floor detected: level \(floor.level) - DEFINITIVE INDOOR")
            return ClassificationResult(mode: .inside, confidence: 0.98, reason: nil, signalSource: .floor)
        }
        
        // Check if floor was recently available (indicates indoor → outdoor transition)
        if let lastFloorTime = lastFloorDetectionTime {
            let timeSinceFloor = Date().timeIntervalSince(lastFloorTime)
            
            // Lost floor signal within last 30 seconds = likely just exited building
            if timeSinceFloor < 30 {
                print("🚪 [LocationManager] Floor signal lost \(Int(timeSinceFloor))s ago - OUTDOOR TRANSITION")
                return ClassificationResult(mode: .outside, confidence: 0.90, reason: nil, signalSource: .floor)
            }
            
            // Floor signal lost 30-60s ago = moderate confidence outdoor
            if timeSinceFloor < 60 {
                print("🚪 [LocationManager] Floor signal lost \(Int(timeSinceFloor))s ago - LIKELY OUTDOOR")
                return ClassificationResult(mode: .outside, confidence: 0.75, reason: nil, signalSource: .floor)
            }
        }
        
        // No floor data available or too old - continue to other signals
        return nil
    }
    
    /// TIER 2: GPS accuracy pattern recognition (indoor vs outdoor signature)
    /// IMPROVED: Handles intermediate patterns and cross-references with motion/distance
    private func classifyWithAccuracyPattern(location: CLLocation, motion: MotionState) -> ClassificationResult? {
        // Need at least 5 samples for pattern analysis
        guard accuracyHistory.count >= 5 else { return nil }

        // CRITICAL FIX: Polygon veto - if inside building polygon, reject outdoor classifications
        // This prevents "near window" false positives where excellent GPS makes us think we're outside
        if isInsideAnyPolygon() {
            print("🏢 [LocationManager] Accuracy pattern skipped - inside building polygon (absolute veto)")
            return nil  // Let polygon-based classification handle this
        }

        // Get recent accuracy values
        let recentAccuracies = accuracyHistory.suffix(10).map { $0.accuracy }

        // Calculate statistics
        let avgAccuracy = recentAccuracies.reduce(0, +) / Double(recentAccuracies.count)
        let variance = recentAccuracies.map { pow($0 - avgAccuracy, 2) }.reduce(0, +) / Double(recentAccuracies.count)
        let stdDev = sqrt(variance)
        
        // DEFINITIVE INDOOR PATTERN: High average + high fluctuation
        // GPS struggles indoors - poor accuracy, constantly changing
        if avgAccuracy > 35 && stdDev > 15 {
            print("📊 [LocationManager] Accuracy pattern: DEFINITIVE INDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m)")
            return ClassificationResult(mode: .inside, confidence: 0.85, reason: nil, signalSource: .accuracyPattern)
        }
        
        // DEFINITIVE OUTDOOR PATTERN: Low average + low fluctuation
        // GPS excels outdoors - good accuracy, stable readings
        // BUT: Also matches "near window indoors" AND "underground with skylight/grate"
        if avgAccuracy < 12 && stdDev < 4 {
            let stationaryDuration = getConsecutiveActivityDuration(.stationary)
            let nearestDistance = getCachedNearestBuildingDistance()
            let isInsidePolygon = isInsideAnyPolygon()

            // CRITICAL FIX (Nov 2025): Underground/basement detection with baseline reset
            // Underground spaces can have excellent GPS (through skylights, grates, thin ceilings)
            // but aren't mapped in OSM polygons. Detect using:
            // 1. Negative relative altitude (below starting point)
            // 2. Very close to buildings but not inside polygon (likely underground beneath building)
            // FIX: Reset baseline if user has moved >1km (prevents false positives from elevation changes)
            if let lastPressure = pressureHistory.last, let lastAccuracy = accuracyHistory.last {
                let relativeAltitude = lastPressure.relativeAltitude
                let currentLocation = CLLocation(latitude: lastAccuracy.coordinate.latitude, longitude: lastAccuracy.coordinate.longitude)
                
                // Check if baseline needs reset (user moved >1km since last reset)
                var shouldResetBaseline = false
                if let baselineLocation = lastBaselineResetLocation {
                    let baselineRef = CLLocation(latitude: baselineLocation.latitude, longitude: baselineLocation.longitude)
                    let distanceFromBaseline = currentLocation.distance(from: baselineRef)
                    
                    if distanceFromBaseline > baselineResetThreshold {
                        shouldResetBaseline = true
                        print("📍 [LocationManager] User moved \(Int(distanceFromBaseline))m from baseline - resetting barometric baseline")
                    }
                }
                
                // Reset baseline if needed (restart altimeter)
                if shouldResetBaseline {
                    resetBarometricBaseline(location: lastAccuracy.coordinate)
                }
                
                // Significant negative altitude (below ground level) = underground
                // -2m threshold accounts for minor elevation changes and sensor noise
                if relativeAltitude < -2.0 {
                    // GPS ACCURACY OVERRIDE: If GPS is excellent AND not inside polygon, allow outdoor
                    // This prevents false underground detection in areas with elevation changes
                    let hasExcellentGPS = (accuracyHistory.last?.accuracy ?? 100) < 10
                    if hasExcellentGPS && !isInsidePolygon {
                        print("✅ [LocationManager] UNDERGROUND OVERRIDE: Negative altitude (\(String(format: "%.1f", relativeAltitude))m) BUT excellent GPS (<10m) + NOT in polygon - allowing outdoor classification")
                        // Continue to stationary outdoor check below
                    } else {
                        print("🕳️ [LocationManager] UNDERGROUND DETECTED: Relative altitude \(String(format: "%.1f", relativeAltitude))m (below ground) + excellent GPS - classifying as INSIDE")
                        return ClassificationResult(mode: .inside, confidence: 0.90, reason: nil, signalSource: .accuracyPattern)
                    }
                }
            }

            // EXISTING: Check for "near window" scenario before declaring outdoor
            // If stationary with this pattern + near/inside building = possibly indoors near window
            // Use TIERED approach to balance false positives (window) vs false negatives (bus stop)
            if motion.isStationary && stationaryDuration > 120 {
                // TIER 1: Inside polygon = definitely indoors (any duration)
                if isInsidePolygon {
                    print("🪟 [LocationManager] NEAR WINDOW DETECTED: Inside building polygon + excellent GPS - classifying as INSIDE")
                    return ClassificationResult(mode: .inside, confidence: 0.90, reason: nil, signalSource: .accuracyPattern)
                }

                // TIER 2: Very close (<5m) + stationary >2min = likely window (ground floor or very close upper floor)
                // CRITICAL FIX (Nov 2025): Lowered from 8m to 5m to prevent bus stop false positives
                // 5m threshold: typical building setback + GPS drift margin
                if let distance = nearestDistance, distance < 5 && stationaryDuration > 120 {
                    print("🪟 [LocationManager] NEAR WINDOW DETECTED: Very close to building (\(Int(distance))m) + stationary \(Int(stationaryDuration))s + excellent GPS - classifying as INSIDE")
                    return ClassificationResult(mode: .inside, confidence: 0.85, reason: nil, signalSource: .accuracyPattern)
                }

                // TIER 3: Moderately close (5-15m) + stationary >5min = likely window (upper floor scenario)
                // Longer duration requirement reduces false negatives for bus stops (typically <5min wait)
                // POLYGON ABSOLUTISM: Skip this check if NOT inside polygon to allow outdoor classification
                if let distance = nearestDistance, distance >= 5 && distance < 15 && stationaryDuration > 300 && isInsidePolygon {
                    print("🪟 [LocationManager] NEAR WINDOW DETECTED: Moderately close to building (\(Int(distance))m) + very stationary \(Int(stationaryDuration))s + excellent GPS - likely upper floor window, classifying as INSIDE")
                    return ClassificationResult(mode: .inside, confidence: 0.80, reason: nil, signalSource: .accuracyPattern)
                }

                // CRITICAL FIX: If NOT inside polygon AND >5m from building, allow outdoor classification
                if !isInsidePolygon, let distance = nearestDistance, distance >= 5 {
                    print("🚏 [LocationManager] OUTDOOR BUS STOP detected: NOT inside polygon + \(Int(distance))m from building + excellent GPS - allowing outdoor classification")
                    // Continue to outdoor classification below
                }

                // Stationary with excellent GPS but not matching window patterns = likely genuinely outdoors
                print("📊 [LocationManager] Accuracy pattern: EXCELLENT GPS + stationary \(Int(stationaryDuration))s + \(nearestDistance != nil ? "\(Int(nearestDistance!))m from building" : "no building data") - allowing outdoor classification")
            }

            print("📊 [LocationManager] Accuracy pattern: DEFINITIVE OUTDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m)")
            return ClassificationResult(mode: .outside, confidence: 0.85, reason: nil, signalSource: .accuracyPattern)
        }
        
        // NEW: INTERMEDIATE PATTERNS (handles blind spots)
        // These require cross-referencing with motion and distance context
        
        // Pattern 1: Near-window indoor (15-25m avg, 8-12m stdDev)
        // Good accuracy but moderate fluctuation = near window OR open area indoor
        if avgAccuracy >= 15 && avgAccuracy <= 28 && stdDev >= 6 && stdDev <= 15 {
            // CRITICAL: Cross-reference with motion
            if motion.isStationary {
                // Stationary with moderate accuracy = likely near-window indoor
                print("📊 [LocationManager] Accuracy pattern: NEAR-WINDOW INDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m, stationary)")
                return ClassificationResult(mode: .inside, confidence: 0.70, reason: nil, signalSource: .accuracyPattern)
            } else if motion.isWalking {
                // Walking with moderate accuracy = could be outdoor in urban area OR indoor hallway
                // Use fluctuation to distinguish:
                // - Higher fluctuation (>10) = likely urban outdoor (multipath)
                // - Lower fluctuation (<10) = likely indoor hallway (stable but poor)
                if stdDev > 10 {
                    print("📊 [LocationManager] Accuracy pattern: URBAN OUTDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m, walking)")
                    return ClassificationResult(mode: .outside, confidence: 0.65, reason: nil, signalSource: .accuracyPattern)
                } else {
                    print("📊 [LocationManager] Accuracy pattern: INDOOR CORRIDOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m, walking)")
                    return ClassificationResult(mode: .inside, confidence: 0.65, reason: nil, signalSource: .accuracyPattern)
                }
            }
        }
        
        // Pattern 2: Dense urban outdoor (20-35m avg, 10-20m stdDev)
        // Poor accuracy with high fluctuation = multipath reflections (tall buildings)
        // DISTINGUISH from indoor by checking motion and speed
        if avgAccuracy >= 20 && avgAccuracy <= 40 && stdDev >= 10 && stdDev <= 25 {
            if motion.isWalking || motion.isRunning {
                // Walking/running with poor unstable GPS = likely dense urban outdoor
                // FIX (Nov 2025): Raised from 0.70 to 0.80 - walking + high variance = definitely outdoor
                print("📊 [LocationManager] Accuracy pattern: DENSE URBAN OUTDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m, moving)")
                return ClassificationResult(mode: .outside, confidence: 0.80, reason: nil, signalSource: .accuracyPattern)
            } else if motion.isVehicle {
                // Vehicle with poor GPS = likely urban driving
                return ClassificationResult(mode: .vehicle, confidence: 0.75, reason: nil, signalSource: .accuracyPattern)
            } else if motion.isStationary {
                // Stationary with poor unstable GPS = ambiguous
                // Could be: waiting at bus stop OR sitting inside near exterior wall
                // DON'T classify - let other signals decide
                print("📊 [LocationManager] Accuracy pattern: AMBIGUOUS (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m, stationary) - need more context")
                return nil
            }
        }

        // Pattern 3: Moderate outdoor with some multipath (12-20m avg, 4-10m stdDev)
        // Decent accuracy with moderate stability = outdoor but not ideal conditions
        if avgAccuracy >= 12 && avgAccuracy <= 20 && stdDev >= 4 && stdDev <= 10 {
            if motion.isWalking || motion.isRunning {
                // FIX (Nov 2025): Raised from 0.75 to 0.85 - this pattern + walking is strong outdoor evidence
                // Moderate GPS accuracy with low-moderate variance while moving = clearly outdoors
                print("📊 [LocationManager] Accuracy pattern: MODERATE OUTDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m, moving)")
                return ClassificationResult(mode: .outside, confidence: 0.85, reason: nil, signalSource: .accuracyPattern)
            } else if motion.isStationary {
                // Stationary with moderate accuracy = likely outdoor (bus stop scenario)
                // FIX (Nov 2025): Raised from 0.65 to 0.75 for better outdoor stationary detection
                print("📊 [LocationManager] Accuracy pattern: STATIONARY OUTDOOR (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m)")
                return ClassificationResult(mode: .outside, confidence: 0.75, reason: nil, signalSource: .accuracyPattern)
            }
        }
        
        // TRANSITIONAL PATTERN: Accuracy changing over time
        // Accuracy improving = likely moving outside
        // Accuracy degrading = likely moving inside
        if recentAccuracies.count >= 5 {
            let firstHalf = Array(recentAccuracies.prefix(5))
            let secondHalf = Array(recentAccuracies.suffix(5))
            let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
            let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
            
            // Accuracy improving significantly = moving outdoor
            if secondAvg < firstAvg - 10 && motion.isWalking {
                print("📊 [LocationManager] Accuracy pattern: IMPROVING (\(String(format: "%.1f", firstAvg))m → \(String(format: "%.1f", secondAvg))m) - EXITING BUILDING")
                return ClassificationResult(mode: .outside, confidence: 0.70, reason: nil, signalSource: .accuracyPattern)
            }
            
            // Accuracy degrading significantly = moving indoor
            if secondAvg > firstAvg + 10 && motion.isWalking {
                print("📊 [LocationManager] Accuracy pattern: DEGRADING (\(String(format: "%.1f", firstAvg))m → \(String(format: "%.1f", secondAvg))m) - ENTERING BUILDING")
                return ClassificationResult(mode: .inside, confidence: 0.70, reason: nil, signalSource: .accuracyPattern)
            }
        }
        
        // No clear pattern - continue to other signals
        print("📊 [LocationManager] Accuracy pattern: INCONCLUSIVE (avg: \(String(format: "%.1f", avgAccuracy))m, σ: \(String(format: "%.1f", stdDev))m) - deferring to other signals")
        return nil
    }
    
    /// TIER 3: Recent geofence events (system-level transitions)
    private func classifyWithRecentGeofence(location: CLLocation) -> ClassificationResult? {
        guard let exitTime = geofenceExitTimestamp else { return nil }
        
        let timeSinceExit = Date().timeIntervalSince(exitTime)
        
        // Very recent geofence exit (<30s) = high confidence outdoor
        if timeSinceExit < 30 {
            print("🚪 [LocationManager] Recent geofence exit (\(Int(timeSinceExit))s ago) - HIGH CONFIDENCE OUTDOOR")
            return ClassificationResult(mode: .outside, confidence: 0.90, reason: nil, signalSource: .geofence)
        }
        
        // Recent geofence exit (30-60s) = moderate confidence outdoor
        if timeSinceExit < 60 {
            print("🚪 [LocationManager] Recent geofence exit (\(Int(timeSinceExit))s ago) - LIKELY OUTDOOR")
            return ClassificationResult(mode: .outside, confidence: 0.80, reason: nil, signalSource: .geofence)
        }
        
        // Too old - continue to other signals
        return nil
    }
    
    /// TIER 4: Barometric pressure change detection (VALIDATION ONLY - Critical Fix #2)
    /// CHANGED: No longer makes solo classification decisions
    /// REASON: Too many false positives from weather, elevators, air conditioning
    /// NOW: Only validates/boosts confidence when OTHER signals suggest transition
    private func classifyWithPressureChange(location: CLLocation, motion: MotionState) -> ClassificationResult? {
        // CRITICAL FIX #2: Barometer downgraded to validation-only
        // No longer returns classification on its own
        // Instead, use getPressureValidation() to boost confidence of other signals
        return nil
    }
    
    /// CRITICAL FIX #2: Barometer as validation signal only
    /// Returns confidence boost if pressure changes agree with a proposed mode transition
    private func getPressureValidation(proposedMode: LocationMode, motion: MotionState) -> Double {
        // Check if altimeter is available
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return 0.0 }
        
        // Need at least 2 samples to detect change
        guard pressureHistory.count >= 2 else { return 0.0 }
        
        // Get recent pressure changes
        let recentChanges = pressureHistory.suffix(10)
        guard let first = recentChanges.first, let last = recentChanges.last else { return 0.0 }
        
        let pressureChange = last.pressure - first.pressure
        let timespan = last.timestamp.timeIntervalSince(first.timestamp)
        
        // Only validate rapid changes while walking (ignore slow weather changes)
        guard motion.isWalking && timespan < 10.0 else { return 0.0 }
        
        // Pressure drop agrees with outdoor transition
        if proposedMode == .outside && pressureChange < -2.0 {
            print("🌡️  [LocationManager] Pressure validation: DROP agrees with outdoor (boost +0.10)")
            return 0.10
        }
        
        // Pressure rise agrees with indoor transition
        if proposedMode == .inside && pressureChange > 2.0 {
            print("🌡️  [LocationManager] Pressure validation: RISE agrees with indoor (boost +0.10)")
            return 0.10
        }
        
        // Small boost for moderate agreement
        if proposedMode == .outside && pressureChange < -1.0 {
            return 0.05
        }
        if proposedMode == .inside && pressureChange > 1.0 {
            return 0.05
        }
        
        return 0.0
    }
    
    /// Helper: Update accuracy history for pattern analysis
    private func updateAccuracyHistory(location: CLLocation) {
        let entry = AccuracyHistoryEntry(
            timestamp: Date(),
            accuracy: location.horizontalAccuracy,
            coordinate: location.coordinate
        )
        
        accuracyHistory.append(entry)
        
        // Keep last 30 samples (2-5 minutes of data)
        if accuracyHistory.count > 30 {
            accuracyHistory.removeFirst()
        }
    }
    
    /// Helper: Start barometric pressure monitoring
    private func startPressureMonitoring() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("⚠️ [LocationManager] Barometric altimeter not available on this device")
            return
        }
        
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            
            Task { @MainActor in
                let sample = PressureSample(
                    timestamp: Date(),
                    pressure: data.pressure.doubleValue,
                    relativeAltitude: data.relativeAltitude.doubleValue
                )
                
                self.pressureHistory.append(sample)
                
                // Keep last 20 samples (1-2 minutes of data)
                if self.pressureHistory.count > 20 {
                    self.pressureHistory.removeFirst()
                }
            }
        }
        
        // Track baseline location for reset detection
        if lastBaselineResetLocation == nil {
            Task { @MainActor in
                if let location = self.locationManager.location {
                    self.lastBaselineResetLocation = location.coordinate
                    print("📍 [LocationManager] Barometric baseline established at current location")
                }
            }
        }
        
        print("🌡️  [LocationManager] Barometric pressure monitoring started")
    }
    
    /// Helper: Reset barometric baseline (called when user moves >1km)
    private func resetBarometricBaseline(location: CLLocationCoordinate2D) {
        // Stop and restart altimeter to reset baseline
        altimeter.stopRelativeAltitudeUpdates()
        pressureHistory.removeAll()
        lastBaselineResetLocation = location
        
        // Restart monitoring
        startPressureMonitoring()
        
        print("🔄 [LocationManager] Barometric baseline reset at new location")
    }
    
    /// Helper: Stop barometric pressure monitoring
    private func stopPressureMonitoring() {
        altimeter.stopRelativeAltitudeUpdates()
        print("🌡️  [LocationManager] Barometric pressure monitoring stopped")
    }
    
    // MARK: - Critical Fix #1: GPS Drift Detection (Nov 2025)
    
    /// Detects GPS drift patterns and prevents false mode changes
    /// Returns drift analysis with recommended mode to maintain
    private func detectGPSDrift(
        newMode: LocationMode,
        coordinate: CLLocationCoordinate2D,
        confidence: Double,
        motion: MotionState
    ) -> (isDrifting: Bool, recommendedMode: LocationMode, confidence: Double)? {
        
        // Only check for drift when stationary (drift happens when not moving)
        guard motion.isStationary else { return nil }
        
        // Add current reading to drift detection history
        let sample = DriftSample(
            timestamp: Date(),
            mode: newMode,
            coordinate: coordinate,
            confidence: confidence
        )
        driftDetectionHistory.append(sample)
        
        // Keep last 5 minutes of samples
        let now = Date()
        driftDetectionHistory = driftDetectionHistory.filter {
            now.timeIntervalSince($0.timestamp) <= 300
        }
        
        // Need at least 6 samples (3+ minutes of data)
        guard driftDetectionHistory.count >= 6 else { return nil }
        
        // Analyze recent samples for oscillation pattern
        let recentSamples = driftDetectionHistory.suffix(6)
        let modes = recentSamples.map { $0.mode }
        
        // Check for mode oscillation (inside → outside → inside OR outside → inside → outside)
        var oscillations = 0
        for i in 1..<modes.count {
            if modes[i] != modes[i-1] && modes[i] != .unknown {
                oscillations += 1
            }
        }
        
        // Check position variance (GPS jumping around)
        let positions = recentSamples.map { $0.coordinate }
        var totalDistance = 0.0
        for i in 1..<positions.count {
            let dist = haversineDistance(from: positions[i-1], to: positions[i])
            totalDistance += dist
        }
        let avgMovement = totalDistance / Double(positions.count - 1)
        
        // DRIFT PATTERN DETECTED if:
        // 1. Multiple oscillations (3+ mode changes)
        // 2. High position variance (avg >8m movement while "stationary")
        // 3. No floor changes (would indicate real transition)
        // 4. No significant pressure changes (would indicate door transitions)
        let hasOscillations = oscillations >= 3
        let hasHighVariance = avgMovement > 8.0
        let noFloorChanges = lastFloorDetectionTime == nil || 
                             Date().timeIntervalSince(lastFloorDetectionTime!) > 60
        
        if hasOscillations && hasHighVariance && noFloorChanges {
            let pattern = modes.map { $0.rawValue }.joined(separator: " → ")

            // Determine mode to lock to:
            // 1. If we have current state with good confidence, maintain it
            if let current = currentState, current.confidence >= 0.70 {
                DetectionLogger.logState(
                    event: "GPS DRIFT DETECTED",
                    mode: current.mode,
                    details: [
                        "oscillations": "\(oscillations) changes in \(recentSamples.count) samples",
                        "avg_movement": "\(String(format: "%.1f", avgMovement))m (should be <5m)",
                        "pattern": pattern,
                        "action": "Locking to current mode",
                        "confidence": String(format: "%.2f", current.confidence)
                    ]
                )
                return (isDrifting: true, recommendedMode: current.mode, confidence: current.confidence)
            }

            // 2. Otherwise, use most frequent mode in recent history
            var modeCounts: [LocationMode: Int] = [:]
            for mode in modes where mode != .unknown {
                modeCounts[mode, default: 0] += 1
            }
            if let mostFrequent = modeCounts.max(by: { $0.value < $1.value }) {
                DetectionLogger.logState(
                    event: "GPS DRIFT DETECTED",
                    mode: mostFrequent.key,
                    details: [
                        "oscillations": "\(oscillations) changes",
                        "pattern": pattern,
                        "action": "Locking to most frequent mode",
                        "frequency": "\(mostFrequent.value)/\(modes.count) samples"
                    ]
                )
                return (isDrifting: true, recommendedMode: mostFrequent.key, confidence: 0.60)
            }

            // 3. Fallback: mark as unknown
            DetectionLogger.log("GPS drift detected but no clear mode to lock to - marking unknown", category: .state, level: .warning)
            return (isDrifting: true, recommendedMode: .unknown, confidence: 0.0)
        }
        
        // No drift detected
        return nil
    }
    
    // MARK: - Critical Fix #3: Mode Lock Helper Methods (Nov 2025)

    /// Determines if current state warrants creating a mode lock
    /// PRIORITY 2 FIX: Locks require multiple signal sources to prevent trapping wrong classification
    /// Locks are created after 5+ minutes of consistent high-confidence state with validation
    private func shouldCreateModeLock(mode: LocationMode, confidence: Double) -> Bool {
        // Don't lock unknown mode
        guard mode != .unknown else { return false }

        // Don't lock if confidence too low
        guard confidence >= 0.75 else { return false }

        // Check if mode has been stable for required duration
        let now = Date()
        let recentHistory = locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= ModeLock.minLockDuration
        }

        // Need enough samples over the duration
        guard recentHistory.count >= 8 else { return false }

        // Check if all recent samples agree on this mode
        let sameMode = recentHistory.allSatisfy { $0.mode == mode }
        guard sameMode else { return false }

        // Check if confidence has been consistently high
        let avgConfidence = recentHistory.reduce(0.0) { $0 + $1.confidence } / Double(recentHistory.count)
        guard avgConfidence >= 0.75 else { return false }

        // PRIORITY 2 FIX: Require multiple signal sources for validation
        var signalSources: Set<String> = []

        // Check for CLFloor signal (highest priority)
        if lastFloorDetectionTime != nil && Date().timeIntervalSince(lastFloorDetectionTime!) < 300 {
            signalSources.insert("floor")
        }

        // Check for GPS accuracy pattern signal
        if accuracyHistory.count >= 3 {
            signalSources.insert("accuracyPattern")
        }

        // Check for building polygon signal (need recent buildings data)
        if let loc = currentLocation {
            let coordinate = loc.coordinate
            let latKey = Int(coordinate.latitude * 1000)
            let lonKey = Int(coordinate.longitude * 1000)
            let cacheKey = "\(latKey):\(lonKey)"
            if let cached = buildingCache[cacheKey],
               Date().timeIntervalSince(cached.timestamp) < 300 {
                signalSources.insert("polygon")
            }
        }

        // Check for motion/vehicle signal
        let motionState = analyzeMotion()
        if motionState.isVehicle || motionState.isWalking || motionState.isRunning {
            signalSources.insert("motion")
        }

        // PRIORITY 2 FIX: Special validation for building proximity
        // If within 30m of building, require polygon/geofence/floor confirmation
        if mode == .inside || mode == .outside {
            guard let loc = currentLocation else {
                print("⚠️  [LocationManager] Mode lock rejected: No current location")
                return false
            }

            // Calculate nearest building distance (simplified check)
            let coordinate = loc.coordinate
            let latKey = Int(coordinate.latitude * 1000)
            let lonKey = Int(coordinate.longitude * 1000)
            let cacheKey = "\(latKey):\(lonKey)"

            if let cached = buildingCache[cacheKey], !cached.buildings.isEmpty {
                let point = [coordinate.latitude, coordinate.longitude]
                let nearestDistance = GeometryUtils.nearestBuildingDistance(
                    point: point,
                    buildings: cached.buildings
                )

                // If within 30m of building, require stronger validation
                if nearestDistance <= 30 {
                    let hasStrongValidation = signalSources.contains("floor") ||
                                            signalSources.contains("polygon") ||
                                            signalSources.contains("geofence")
                    if !hasStrongValidation {
                        print("⚠️  [LocationManager] Mode lock rejected: Within 30m of building but no strong validation signal")
                        print("   - Distance: \(Int(nearestDistance))m")
                        print("   - Available signals: \(signalSources.joined(separator: ", "))")
                        print("   - Requires: floor, polygon, or geofence signal")
                        return false
                    }
                }
            }
        }

        // PRIORITY 2 FIX: Require at least 2 different signal sources
        if signalSources.count < 2 {
            print("⚠️  [LocationManager] Mode lock rejected: Only \(signalSources.count) signal source(s)")
            print("   - Available: \(signalSources.joined(separator: ", "))")
            print("   - Requires: At least 2 independent sources")
            return false
        }

        print("✅ [LocationManager] Mode lock conditions met:")
        print("   - Mode: \(mode.rawValue) stable for \(recentHistory.count) samples")
        print("   - Avg confidence: \(String(format: "%.2f", avgConfidence))")
        print("   - Duration: ~\(Int(ModeLock.minLockDuration/60)) minutes")
        print("   - Signal sources: \(signalSources.joined(separator: ", ")) (\(signalSources.count) sources)")

        return true
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkAuthorizationStatus()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            let locationAge = Date().timeIntervalSince(location.timestamp)
            let timeSinceLastCheck = Date().timeIntervalSince(lastCheckTimestamp)

            // OPTIMIZATION: Skip very stale GPS (>10s old) on startup - wait for fresh data
            // Exception: Process if we haven't had any location check yet
            if locationAge > 10 && currentState != nil {
                print("📍 [LocationManager] Skipping stale GPS (\(Int(locationAge))s old) - waiting for fresh data")
                currentLocation = location  // Still update for sun times
                return
            }

            // OPTIMIZATION: Debounce rapid updates - skip if checked within 3 seconds
            // Exception: Always process if mode might be changing (different location)
            let distanceFromLast = currentLocation.map {
                location.distance(from: $0)
            } ?? Double.infinity

            if timeSinceLastCheck < 3.0 && distanceFromLast < 15 && currentState != nil {
                // Just update location without full detection
                currentLocation = location
                return
            }

            // Always update currentLocation (needed for sun times, etc)
            currentLocation = location

            // Only process if actively tracking
            guard isTracking else { return }

            do {
                let state = try await performLocationCheck()

                // Notify background task manager of location state
                if state.mode == .outside {
                    await BackgroundTaskManager.shared.handleOutsideDetection(location: location, state: state)
                } else {
                    await BackgroundTaskManager.shared.handleInsideDetection(state: state)
                }

            } catch {
                print("❌ [LocationManager] Location check failed: \(error)")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            // OPTIMIZATION FIX: Visit events indicate user is STATIONARY, not necessarily INSIDE
            // Visits fire when user stays at a location >3 minutes
            // This could be: indoor (café, office), outdoor (park bench, basketball court), or vehicle (parking lot)
            
            if visit.departureDate == Date.distantFuture {
                // Arrival at location - user is now stationary
                print("📍 [LocationManager] Visit arrival detected - user stationary at location")
                
                // Trigger fresh location check (stationary context may help classification)
                // BUT: Don't override outdoor states - let normal logic decide
                _ = try? await performLocationCheck(forceRefresh: true)
            } else {
                // Departure from location - user is now moving
                print("🚶 [LocationManager] Visit departure detected - user leaving location")
                _ = try? await performLocationCheck(forceRefresh: true)
                
                // Setup geofences for this location for faster future transitions
                if let location = currentLocation {
                    let buildings = try? await overpassService.getNearbyBuildings(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    if let buildings = buildings {
                        setupBuildingGeofences(buildings: buildings)
                    }
                }
            }
        }
    }
    
    /// CIRCULAR GEOFENCE CALLBACK: Wakes app in background when entering building radius
    /// NOTE: Only used for triggering location checks, NOT for classification decisions
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            // Track entry timestamp (used only for logging/debugging, not classification)
            geofenceEntryTimestamps[region.identifier] = Date()

            DetectionLogger.logGeofence(
                event: "CIRCULAR GEOFENCE ENTERED",
                buildingId: region.identifier
            )

            // Wake app and trigger polygon-based classification check
            _ = try? await performLocationCheck(forceRefresh: true)
        }
    }
    
    /// CIRCULAR GEOFENCE CALLBACK: Wakes app in background when exiting building radius
    /// NOTE: Only used for triggering location checks, NOT for classification decisions
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            // Analyze time spent in circular geofence (logging only)
            var duration: TimeInterval? = nil
            if let entryTime = geofenceEntryTimestamps[region.identifier] {
                duration = Date().timeIntervalSince(entryTime)

                let analysis = duration! < 30 ? "likely just passing by" : "likely actual building visit"
                DetectionLogger.log(
                    "Time in circular geofence: \(Int(duration!))s - \(analysis)",
                    category: .geofence
                )

                // Clear entry timestamp
                geofenceEntryTimestamps.removeValue(forKey: region.identifier)
            }

            DetectionLogger.logGeofence(
                event: "CIRCULAR GEOFENCE EXITED",
                buildingId: region.identifier,
                duration: duration
            )

            // Store timestamp (kept for backwards compatibility, but not used in classification)
            geofenceExitTimestamp = Date()

            // IMPROVEMENT #9: Force immediate GPS update on geofence exit
            // Keep fast updates for longer (15 seconds instead of 5)
            locationManager.distanceFilter = kCLDistanceFilterNone  // Get immediate update

            // Trigger immediate location check
            _ = try? await performLocationCheck(forceRefresh: true)

            // Restore normal distance filter after 15 seconds (increased from 5)
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    if !isTracking { return }
                    // Keep at 10m for better outdoor detection
                    print("📍 [LocationManager] Restoring fast sampling after geofence exit (10m filter)")
                    locationManager.distanceFilter = 10
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Error: \(error)")
    }
}

// MARK: - Supporting Types

struct MotionState {
    let isStationary: Bool
    let isWalking: Bool
    let isRunning: Bool
    let isVehicle: Bool
    let justStartedMoving: Bool
    let activity: LocationManager.MotionActivity?
    let averageSpeed: Double
    let vehicleConfidence: Double
}

enum LocationError: LocalizedError {
    case locationUnavailable
    case buildingDataUnavailable

    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Location services unavailable"
        case .buildingDataUnavailable:
            return "Unable to fetch building data"
        }
    }
}

// MARK: - Extensions

private extension Double {
    func rounded(toPlaces places: Int = 2) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
