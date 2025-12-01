import Foundation
import CoreLocation
import CoreMotion
import Combine

// MARK: - Location Service

/// Service for CLLocationManager, barometric pressure, and manual override
/// Handles GPS updates, pressure monitoring, and user-initiated indoor override
@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    // MARK: - Published Properties

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isAuthorized = false
    @Published private(set) var isTracking = false

    // MARK: - Core Location

    private let locationManager = CLLocationManager()

    /// Expose CLLocationManager for geofence registration
    var locationManagerInstance: CLLocationManager {
        return locationManager
    }

    // MARK: - Barometric Altimeter

    private let altimeter = CMAltimeter()
    private var isPressureMonitoring = false

    // MARK: - Tracking State

    private(set) var trackingStartTime: Date?
    private(set) var lastValidGPSTimestamp = Date()

    /// True if in first 2 minutes of tracking (conservative thresholds apply)
    var isInStartupPhase: Bool {
        guard let startTime = trackingStartTime else { return true }
        return Date().timeIntervalSince(startTime) < 120
    }

    // MARK: - Manual Override

    private var manualIndoorOverride: Bool = false
    private var manualOverrideStartTime: Date?
    private var manualOverrideDuration: TimeInterval = 900 // 15 minutes default
    private let manualOverrideKey = "manualIndoorOverrideState"
    private let userDefaults = UserDefaults.standard

    /// Whether manual override feature is enabled in settings
    var manualOverrideEnabled: Bool = true

    /// Returns true if manual override is currently active
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

    // MARK: - Barometric Baseline

    private var lastBaselineResetLocation: CLLocationCoordinate2D?
    private let baselineResetThreshold: Double = 1000.0  // 1km threshold

    // MARK: - Callbacks

    /// Called when new location is available
    var onLocationUpdate: ((CLLocation) -> Void)?

    /// Called when visiting a location
    var onVisit: ((CLVisit) -> Void)?

    /// Called when entering a geofence region
    var onRegionEnter: ((CLRegion) -> Void)?

    /// Called when exiting a geofence region
    var onRegionExit: ((CLRegion) -> Void)?

    /// Called when pressure sample is available
    var onPressureSample: ((PressureSample) -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()
        setupLocationManager()
        restoreManualOverrideState()
    }

    // MARK: - Setup

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Fast outdoor detection
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false // Never pause
        locationManager.showsBackgroundLocationIndicator = true

        if #available(iOS 14.0, *) {
            locationManager.activityType = .fitness
        }

        checkAuthorizationStatus()
    }

    private func checkAuthorizationStatus() {
        let status = CLLocationManager.authorizationStatus()
        isAuthorized = (status == .authorizedAlways || status == .authorizedWhenInUse)

        if #available(iOS 14.0, *) {
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                print("[LocationService] Reduced accuracy mode detected")
                locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracyUsage")
            }
        }
    }

    // MARK: - Public API

    /// Request location permission
    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Request a one-time location update
    func requestOneTimeLocation() {
        guard isAuthorized else {
            requestLocationPermission()
            return
        }
        locationManager.requestLocation()
    }

    /// Start location updates
    func startLocationUpdates() {
        guard isAuthorized else {
            requestLocationPermission()
            return
        }

        isTracking = true
        trackingStartTime = Date()

        // Start pressure monitoring
        startPressureMonitoring()

        // Primary: Continuous location updates
        locationManager.startUpdatingLocation()

        // Secondary: Significant location changes (500m+ fallback)
        locationManager.startMonitoringSignificantLocationChanges()

        // Tertiary: Visit monitoring (if always authorized)
        if CLLocationManager.authorizationStatus() == .authorizedAlways {
            locationManager.startMonitoringVisits()
        }

        // Request immediate update
        locationManager.requestLocation()

        print("[LocationService] Background location tracking STARTED")
    }

    /// Stop location updates
    func stopLocationUpdates() {
        isTracking = false

        stopPressureMonitoring()

        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()

        print("[LocationService] Background location tracking STOPPED")
    }

    /// Adjust distance filter based on motion and confidence
    func adjustDistanceFilter(isMoving: Bool, confidence: Double) {
        if isMoving {
            // Fast updates when moving
            locationManager.distanceFilter = 10
        } else if confidence >= 0.80 {
            // Less frequent when stationary with high confidence
            locationManager.distanceFilter = 15
        } else {
            // Keep fast when uncertain
            locationManager.distanceFilter = 10
        }
    }

    /// Temporarily disable distance filter for immediate update
    func requestImmediateUpdate() {
        let originalFilter = locationManager.distanceFilter
        locationManager.distanceFilter = kCLDistanceFilterNone

        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await MainActor.run {
                if isTracking {
                    locationManager.distanceFilter = originalFilter
                }
            }
        }
    }

    // MARK: - Manual Override

    /// Activate manual indoor override
    func setManualIndoorOverride(duration: TimeInterval = 900) {
        guard manualOverrideEnabled else {
            print("[LocationService] Manual override is disabled in settings")
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

        print("[LocationService] Manual indoor override activated for \(Int(duration/60)) minutes")
    }

    /// Clear manual indoor override
    func clearManualOverride() {
        manualIndoorOverride = false
        manualOverrideStartTime = nil

        userDefaults.removeObject(forKey: manualOverrideKey)

        print("[LocationService] Manual override cleared")
    }

    /// Extend active manual override
    func extendManualOverride(additionalSeconds: TimeInterval = 900) {
        guard manualIndoorOverride, let startTime = manualOverrideStartTime else {
            print("[LocationService] No active override to extend")
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        manualOverrideDuration = elapsed + additionalSeconds

        // Update persistence
        let overrideDict: [String: Any] = [
            "isActive": true,
            "startTime": startTime.timeIntervalSince1970,
            "duration": manualOverrideDuration
        ]
        userDefaults.set(overrideDict, forKey: manualOverrideKey)

        print("[LocationService] Manual override extended by \(Int(additionalSeconds/60)) minutes")
    }

    private func restoreManualOverrideState() {
        guard let overrideDict = userDefaults.dictionary(forKey: manualOverrideKey),
              let isActive = overrideDict["isActive"] as? Bool,
              isActive,
              let startTimestamp = overrideDict["startTime"] as? TimeInterval,
              let duration = overrideDict["duration"] as? TimeInterval else {
            return
        }

        let startTime = Date(timeIntervalSince1970: startTimestamp)
        let elapsed = Date().timeIntervalSince(startTime)

        if elapsed < duration {
            manualIndoorOverride = true
            manualOverrideStartTime = startTime
            manualOverrideDuration = duration

            let remaining = Int((duration - elapsed) / 60)
            print("[LocationService] Manual override restored: \(remaining) minutes remaining")
        } else {
            userDefaults.removeObject(forKey: manualOverrideKey)
        }
    }

    // MARK: - Pressure Monitoring

    private func startPressureMonitoring() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("[LocationService] Barometric altimeter not available")
            return
        }

        guard !isPressureMonitoring else { return }

        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] data, error in
            guard let self = self, let data = data else { return }

            Task { @MainActor in
                let sample = PressureSample(
                    timestamp: Date(),
                    pressure: data.pressure.doubleValue,
                    relativeAltitude: data.relativeAltitude.doubleValue
                )

                self.onPressureSample?(sample)
            }
        }

        isPressureMonitoring = true

        // Track baseline location for reset detection
        if lastBaselineResetLocation == nil, let location = locationManager.location {
            lastBaselineResetLocation = location.coordinate
        }

        print("[LocationService] Barometric pressure monitoring started")
    }

    private func stopPressureMonitoring() {
        altimeter.stopRelativeAltitudeUpdates()
        isPressureMonitoring = false
        print("[LocationService] Barometric pressure monitoring stopped")
    }

    /// Reset barometric baseline (called when user moves >1km)
    func resetBarometricBaseline() {
        guard let location = currentLocation else { return }

        altimeter.stopRelativeAltitudeUpdates()
        lastBaselineResetLocation = location.coordinate

        // Restart monitoring
        startPressureMonitoring()

        print("[LocationService] Barometric baseline reset at new location")
    }

    /// Check if baseline reset is needed (moved >1km)
    func checkBaselineReset() {
        guard let current = currentLocation,
              let baseline = lastBaselineResetLocation else {
            return
        }

        let distance = GeometryUtils.haversineDistance(
            lat1: baseline.latitude,
            lon1: baseline.longitude,
            lat2: current.coordinate.latitude,
            lon2: current.coordinate.longitude
        )

        if distance > baselineResetThreshold {
            resetBarometricBaseline()
        }
    }

    // MARK: - GPS Validity

    /// Update last valid GPS timestamp
    func recordValidGPS() {
        lastValidGPSTimestamp = Date()
    }

    /// Check if GPS has been unavailable for too long
    func isGPSUnavailable(thresholdSeconds: TimeInterval = 300) -> Bool {
        return Date().timeIntervalSince(lastValidGPSTimestamp) > thresholdSeconds
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            checkAuthorizationStatus()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location
            onLocationUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            onVisit?(visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            onRegionEnter?(region)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            onRegionExit?(region)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationService] Error: \(error)")
    }
}
