import Foundation
import CoreLocation
import Combine

// MARK: - Location Manager (Facade)

/// Facade for the refactored location detection system
/// Provides the same public API as the original LocationManager for backward compatibility
/// Delegates to the new modular services: LocationService, MotionService, DetectionEngine
@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    // MARK: - Published Properties (Backward Compatible)

    @Published private(set) var currentLocation: CLLocation?
    @Published var locationMode: LocationMode = .unknown
    @Published var confidence: Double = 0.0
    @Published private(set) var isAuthorized: Bool = false
    @Published var uvIndex: Double = 0.0
    @Published private(set) var isTracking: Bool = false
    @Published var uncertaintyReason: LocationUncertaintyReason?

    // MARK: - Services

    private let locationService = LocationService.shared
    private let motionService = MotionService.shared
    private let buildingService = BuildingDataService.shared
    private let detectionEngine = DetectionEngine.shared
    private let weatherService = WeatherService.shared

    /// Access to detection history via DetectionEngine (single source of truth)
    private var detectionHistory: DetectionHistory {
        detectionEngine.history
    }

    // MARK: - State

    private var currentState: DetectionState?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Access (for permission upgrades)

    var locationManagerInstance: CLLocationManager {
        return locationService.locationManagerInstance
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        setupBindings()
        setupServiceForwarding()
    }

    private func setupServiceForwarding() {
        // Forward published values from LocationService
        locationService.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.currentLocation = location
            }
            .store(in: &cancellables)

        locationService.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                self?.isAuthorized = authorized
            }
            .store(in: &cancellables)

        locationService.$isTracking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracking in
                self?.isTracking = tracking
            }
            .store(in: &cancellables)

        // Forward UV index from WeatherService cache
        // Periodically sync the UV index for UI display
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateUVIndexFromCache()
            }
        }
    }

    private func updateUVIndexFromCache() async {
        guard let location = currentLocation else { return }

        do {
            let fetchedUVIndex = try await weatherService.getCurrentUVIndex(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            uvIndex = fetchedUVIndex
        } catch {
            // Keep existing cached value on error
        }
    }

    private func setupBindings() {
        // Forward location updates to detection engine
        locationService.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                await self?.handleLocationUpdate(location)
            }
        }

        // Forward pressure samples to history
        locationService.onPressureSample = { [weak self] sample in
            self?.detectionHistory.addPressureSample(sample)
        }

        // Forward geofence events
        locationService.onRegionEnter = { [weak self] region in
            self?.detectionHistory.recordGeofenceEntry(regionId: region.identifier)
            Task { @MainActor in
                await self?.performLocationCheck(forceRefresh: true)
            }
        }

        locationService.onRegionExit = { [weak self] region in
            self?.detectionHistory.recordGeofenceExit(regionId: region.identifier)
            self?.locationService.requestImmediateUpdate()
            Task { @MainActor in
                await self?.performLocationCheck(forceRefresh: true)
            }
        }

        // Forward visit events
        locationService.onVisit = { [weak self] visit in
            Task { @MainActor in
                await self?.performLocationCheck(forceRefresh: true)
            }
        }

        // Handle significant motion changes
        motionService.onSignificantMotionChange = { [weak self] _, _ in
            Task { @MainActor in
                await self?.performLocationCheck(forceRefresh: true)
            }
        }
    }

    // MARK: - Public API (Backward Compatible)

    func requestLocationPermission() {
        locationService.requestLocationPermission()
    }

    func requestOneTimeLocation() {
        locationService.requestOneTimeLocation()
    }

    func startLocationUpdates() {
        locationService.startLocationUpdates()
        motionService.startMonitoring()
    }

    func stopLocationUpdates() {
        locationService.stopLocationUpdates()
        motionService.stopMonitoring()
    }

    // MARK: - Manual Override API

    func setManualIndoorOverride(duration: TimeInterval = 900) {
        locationService.setManualIndoorOverride(duration: duration)
        Task {
            await performLocationCheck(forceRefresh: true)
        }
    }

    func clearManualOverride() {
        locationService.clearManualOverride()
        Task {
            await performLocationCheck(forceRefresh: true)
        }
    }

    func extendManualOverride(additionalSeconds: TimeInterval = 900) {
        locationService.extendManualOverride(additionalSeconds: additionalSeconds)
    }

    var isManualOverrideActive: Bool {
        locationService.isManualOverrideActive
    }

    var manualOverrideRemainingTime: TimeInterval? {
        locationService.manualOverrideRemainingTime
    }

    // MARK: - State Access

    /// Get current detection state
    func getCurrentState(forceRefresh: Bool = false) async throws -> LegacyLocationState {
        if let state = currentState, !forceRefresh {
            return state.asLegacyState
        }

        guard let location = locationService.currentLocation else {
            throw LocationError.locationUnavailable
        }

        let state = try await detectionEngine.classify(location: location)
        currentState = state

        // Update published properties
        locationMode = state.mode
        confidence = state.confidence

        return state.asLegacyState
    }

    /// Clear all caches
    func clearCache() {
        currentState = nil
        detectionHistory.clearAllHistory()
        buildingService.clearCache()
        motionService.clearHistory()
        uncertaintyReason = nil
    }

    // MARK: - Polygon-Based Geofencing Helpers

    func isInsideAnyPolygon() -> Bool {
        detectionHistory.isInsideAnyPolygon()
    }

    func isInsidePolygonSustained() -> (Bool, TimeInterval?) {
        detectionHistory.isInsidePolygonSustained()
    }

    func hasRecentPolygonExit() -> (Bool, TimeInterval?) {
        detectionHistory.hasRecentPolygonExit()
    }

    func getCurrentPolygonDuration() -> TimeInterval? {
        detectionHistory.getCurrentPolygonDuration()
    }

    func hasRecentFloorDetection(within seconds: TimeInterval = 300) -> Bool {
        detectionHistory.hasRecentFloorDetection(withinSeconds: seconds)
    }

    /// Check for sustained excellent GPS accuracy (fast-path outdoor detection)
    func checkSustainedExcellentGPS() -> (hasExcellent: Bool, avgAccuracy: Double, duration: TimeInterval) {
        detectionHistory.checkSustainedExcellentGPS()
    }

    func getCachedNearestBuildingDistance() -> Double? {
        guard let location = locationService.currentLocation else { return nil }
        return buildingService.getCachedNearestBuildingDistance(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    // MARK: - Geofence Setup

    func setupBuildingGeofences(buildings: [OverpassBuilding]) {
        guard let location = locationService.currentLocation else { return }

        _ = buildingService.setupBuildingGeofences(
            buildings: buildings,
            currentLocation: location,
            locationManager: locationService.locationManagerInstance
        )
    }

    // MARK: - Private Methods

    private func handleLocationUpdate(_ location: CLLocation) async {
        guard locationService.isTracking else { return }

        // Debounce rapid updates
        let locationAge = Date().timeIntervalSince(location.timestamp)
        if locationAge > 10 && currentState != nil {
            return
        }

        // Check if barometric baseline needs reset (user moved >1km)
        locationService.checkBaselineReset()

        await performLocationCheck()
    }

    private func performLocationCheck(forceRefresh: Bool = false) async {
        guard let location = locationService.currentLocation else { return }

        do {
            let state = try await detectionEngine.classify(location: location)
            currentState = state

            // Notify BackgroundTaskManager first (it manages locks)
            if state.mode == .outside {
                await BackgroundTaskManager.shared.handleOutsideDetection(
                    location: location,
                    state: state.asLegacyState
                )
            } else {
                await BackgroundTaskManager.shared.handleInsideDetection(
                    state: state.asLegacyState
                )
            }

            // Update published properties AFTER lock state is updated
            // This ensures locationMode reflects effective mode (accounting for vehicle lock)
            let effectiveMode = getEffectiveMode(classifiedMode: state.mode)
            locationMode = effectiveMode
            confidence = state.confidence

        } catch {
            print("[LocationManager] Location check failed: \(error)")
        }
    }

    /// Get effective mode considering tracking locks
    /// Vehicle lock takes priority - if locked, user sees "vehicle" not the raw classification
    private func getEffectiveMode(classifiedMode: LocationMode) -> LocationMode {
        // Vehicle lock takes priority
        if BackgroundTaskManager.shared.vehicleLockActive {
            return .vehicle
        }
        return classifiedMode
    }
}

// MARK: - Location Error

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

// Note: LocationUncertaintyReason is defined in DetectionTypes.swift
