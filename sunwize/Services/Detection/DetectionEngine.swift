import Foundation
import CoreLocation

// MARK: - Detection Engine

/// Core classification engine for indoor/outdoor/vehicle detection
/// Implements multi-tier signal classification with weighted voting
@MainActor
class DetectionEngine: ObservableObject {
    static let shared = DetectionEngine()

    // MARK: - Dependencies

    /// Detection history - exposed for external event forwarding (pressure, geofence events)
    let history: DetectionHistory
    private let motionService: MotionService
    private let buildingService: BuildingDataService
    private let locationService: LocationService
    private let config: DetectionConfig

    // MARK: - State

    @Published private(set) var currentState: DetectionState?

    /// Current mode lock for stability
    private var modeLock: ModeLock?

    /// Tunnel state for maintaining vehicle mode through GPS degradation
    private var tunnelState = TunnelState()

    /// Last check timestamp for debouncing
    private var lastCheckTimestamp = Date.distantPast

    // MARK: - Initialization

    private init() {
        self.history = DetectionHistory()
        self.motionService = MotionService.shared
        self.buildingService = BuildingDataService.shared
        self.locationService = LocationService.shared
        self.config = .default
    }

    // MARK: - Public API

    /// Perform full location classification
    func classify(location: CLLocation) async throws -> DetectionState {
        let coordinate = location.coordinate
        let accuracy = location.horizontalAccuracy
        let speed = location.speed >= 0 ? location.speed : nil

        // Update GPS validity tracking
        if accuracy > 0 && accuracy < 150 {
            locationService.recordValidGPS()
        } else if locationService.isGPSUnavailable() {
            return createUnknownState(
                coordinate: coordinate,
                accuracy: accuracy,
                reason: "gps_unavailable"
            )
        }

        // Update accuracy history
        history.addAccuracyReading(from: location)

        // Get motion state
        if let speed = speed {
            motionService.updateSpeed(speed)
        }
        let motion = motionService.analyzeMotion()

        // Check for tunnel mode
        if let tunnelMode = checkTunnelDetection(
            currentAccuracy: accuracy,
            currentMode: currentState?.mode ?? .unknown,
            motion: motion
        ) {
            return createState(
                mode: tunnelMode,
                confidence: 0.95,
                source: .tunnel,
                reason: "tunnel_mode_maintained",
                coordinate: coordinate,
                accuracy: accuracy,
                speed: speed,
                motion: motion
            )
        }

        // Check for manual override
        if locationService.isManualOverrideActive {
            return createState(
                mode: .inside,
                confidence: 1.0,
                source: .manualOverride,
                reason: "manual_override_active",
                coordinate: coordinate,
                accuracy: accuracy,
                speed: speed,
                motion: motion
            )
        }

        // Fetch buildings and update polygon state
        let buildings: [OverpassBuilding]
        var buildingFetchFailed = false

        do {
            buildings = try await buildingService.fetchNearbyBuildings(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } catch {
            buildingFetchFailed = true
            buildings = []
        }

        // Update polygon occupancy
        history.updatePolygonOccupancy(coordinate: coordinate, buildings: buildings)

        // Setup circular geofences for background wake-up
        if !buildings.isEmpty {
            _ = buildingService.setupBuildingGeofences(
                buildings: buildings,
                currentLocation: location,
                locationManager: locationService.locationManagerInstance
            )
        }

        // Calculate nearest distance
        let nearestDistance = buildings.isEmpty ? Double.infinity :
            buildingService.calculateNearestDistance(coordinate: coordinate, buildings: buildings)

        // Build detection context
        let context = DetectionContext(
            location: location,
            buildings: buildings,
            insidePolygon: buildingService.isInsideAnyBuilding(coordinate: coordinate, buildings: buildings),
            nearestDistance: nearestDistance < 999999 ? nearestDistance : nil,
            vehicleAnalysis: motionService.getVehicleAnalysis(),
            accuracyStats: history.getAccuracyStatistics(),
            motion: motion,
            stationaryDuration: getStationaryDuration(),
            isInStartupPhase: locationService.isInStartupPhase
        )

        // Run multi-tier classification
        let (classification, signalSource) = performClassification(
            context: context,
            buildingDataAvailable: !buildingFetchFailed
        )

        // Check for GPS drift
        var finalMode = classification.mode
        var finalConfidence = classification.confidence

        if let driftResult = history.detectGPSDrift(
            newMode: classification.mode,
            coordinate: coordinate,
            confidence: classification.confidence,
            isStationary: motion.isStationary
        ), driftResult.isDrifting {
            finalMode = driftResult.recommendedMode
            finalConfidence = driftResult.confidence
        }

        // Apply GPS accuracy penalty
        finalConfidence *= getGPSAccuracyFactor(accuracy)

        // Apply pressure validation boost
        if finalMode != .unknown {
            let pressureBoost = getPressureValidation(proposedMode: finalMode, motion: motion)
            if pressureBoost > 0 {
                finalConfidence = min(0.95, finalConfidence + pressureBoost)
            }
        }

        // Create detection state
        let state = createState(
            mode: finalMode,
            confidence: finalConfidence,
            source: signalSource,
            reason: classification.reason,
            coordinate: coordinate,
            accuracy: accuracy,
            speed: speed,
            motion: motion,
            context: context
        )

        // Add to history
        if state.mode != .unknown {
            history.addLocationEntry(from: state, signalSource: signalSource)
        }

        // Check stable mode from history
        if state.mode != .unknown {
            let allowSingleVehicle = state.mode == .vehicle && state.confidence >= 0.85

            if let stableMode = history.getStableModeFromHistory(
                allowSingleSample: allowSingleVehicle,
                isStationary: motion.isStationary
            ) {
                let stableState = DetectionState(
                    mode: stableMode,
                    confidence: min(0.95, max(0.75, state.confidence)),
                    source: signalSource,
                    reason: state.reason,
                    coordinate: coordinate,
                    accuracy: accuracy > 0 ? accuracy : nil,
                    speed: speed,
                    activity: motion.activity,
                    polygonOccupancyDuration: context.insidePolygon != nil ? history.getCurrentPolygonDuration() : nil,
                    isStationaryNearBuilding: motion.isStationary && (nearestDistance < 40),
                    stationaryDuration: getStationaryDuration(),
                    nearestBuildingDistance: nearestDistance < 999999 ? nearestDistance : nil
                )

                currentState = stableState
                return stableState
            }
        }

        // Update mode lock
        evaluateModeLock(state: state, context: context)

        currentState = state
        lastCheckTimestamp = Date()
        return state
    }

    // MARK: - Multi-Tier Classification

    private func performClassification(
        context: DetectionContext,
        buildingDataAvailable: Bool
    ) -> (ClassificationResult, SignalSource) {
        let location = context.location
        let motion = context.motion

        // TIER 1: Floor detection (definitive indoor)
        if let floorResult = classifyWithFloorData(location: location) {
            return (floorResult, .floor)
        }

        // TIER 2: Accuracy pattern (indoor/outdoor signature)
        if let patternResult = classifyWithAccuracyPattern(context: context) {
            return (patternResult, .accuracyPattern)
        }

        // TIER 3: Pressure change (transition detector)
        if let pressureResult = classifyWithPressureChange(context: context) {
            return (pressureResult, .underground)
        }

        // TIER 4: Building data classification
        let result = classifyWithBuildingData(
            context: context,
            buildingDataAvailable: buildingDataAvailable
        )
        let source: SignalSource = buildingDataAvailable ? .polygon : .fallback

        return (result, source)
    }

    // MARK: - TIER 1: Floor Detection

    private func classifyWithFloorData(location: CLLocation) -> ClassificationResult? {
        if let floor = location.floor {
            // Floor detected = DEFINITIVE INDOOR signal
            history.recordFloorDetection(level: floor.level)
            return ClassificationResult(
                mode: .inside,
                confidence: 0.98,
                signalSource: .floor
            )
        }

        // Check if floor was recently available (indicates indoor → outdoor transition)
        if history.hasRecentFloorDetection(withinSeconds: 30) {
            return ClassificationResult(
                mode: .outside,
                confidence: 0.90,
                signalSource: .floor
            )
        }

        if history.hasRecentFloorDetection(withinSeconds: 60) {
            return ClassificationResult(
                mode: .outside,
                confidence: 0.75,
                signalSource: .floor
            )
        }

        return nil
    }

    // MARK: - TIER 2: Accuracy Pattern

    private func classifyWithAccuracyPattern(context: DetectionContext) -> ClassificationResult? {
        let stats = context.accuracyStats
        guard stats.sampleCount >= 5 else { return nil }

        // If inside polygon, skip outdoor classifications
        if history.isInsideAnyPolygon() {
            return nil
        }

        let motion = context.motion

        // DEFINITIVE INDOOR: High average + high fluctuation
        if stats.average > 35 && stats.stdDev > 15 {
            return ClassificationResult(
                mode: .inside,
                confidence: 0.85,
                signalSource: .accuracyPattern
            )
        }

        // DEFINITIVE OUTDOOR: Low average + low fluctuation
        if stats.average < 12 && stats.stdDev < 4 {
            // Check for near-window scenario
            if motion.isStationary && context.stationaryDuration > 120 {
                if let distance = context.nearestDistance, distance < 5 {
                    // Very close to building + stationary = likely window
                    return ClassificationResult(
                        mode: .inside,
                        confidence: 0.85,
                        reason: "near_window_detected",
                        signalSource: .accuracyPattern
                    )
                }
            }

            return ClassificationResult(
                mode: .outside,
                confidence: 0.85,
                signalSource: .accuracyPattern
            )
        }

        // INTERMEDIATE: Near-window indoor pattern
        if stats.average >= 15 && stats.average <= 28 && stats.stdDev >= 6 && stats.stdDev <= 15 {
            if motion.isStationary {
                return ClassificationResult(
                    mode: .inside,
                    confidence: 0.70,
                    signalSource: .accuracyPattern
                )
            } else if motion.isWalking {
                if stats.stdDev > 10 {
                    return ClassificationResult(
                        mode: .outside,
                        confidence: 0.65,
                        signalSource: .accuracyPattern
                    )
                } else {
                    return ClassificationResult(
                        mode: .inside,
                        confidence: 0.65,
                        signalSource: .accuracyPattern
                    )
                }
            }
        }

        // DENSE URBAN: Poor accuracy with high fluctuation
        if stats.average >= 20 && stats.average <= 40 && stats.stdDev >= 10 && stats.stdDev <= 25 {
            if motion.isWalking || motion.isRunning {
                return ClassificationResult(
                    mode: .outside,
                    confidence: 0.80,
                    signalSource: .accuracyPattern
                )
            } else if motion.isVehicle {
                return ClassificationResult(
                    mode: .vehicle,
                    confidence: 0.75,
                    signalSource: .accuracyPattern
                )
            }
        }

        // MODERATE OUTDOOR: Decent accuracy with moderate stability
        if stats.average >= 12 && stats.average <= 20 && stats.stdDev >= 4 && stats.stdDev <= 10 {
            if motion.isWalking || motion.isRunning {
                return ClassificationResult(
                    mode: .outside,
                    confidence: 0.85,
                    signalSource: .accuracyPattern
                )
            } else if motion.isStationary {
                return ClassificationResult(
                    mode: .outside,
                    confidence: 0.75,
                    signalSource: .accuracyPattern
                )
            }
        }

        return nil
    }

    // MARK: - TIER 3: Pressure Change

    private func classifyWithPressureChange(context: DetectionContext) -> ClassificationResult? {
        guard let pressureChange = history.getRecentPressureChange() else {
            return nil
        }

        // Significant negative altitude = underground
        if pressureChange < -2.0 && !context.motion.isWalking {
            // Check for excellent GPS override
            if context.accuracyStats.average < 10 && !history.isInsideAnyPolygon() {
                return nil // Allow other classification
            }

            return ClassificationResult(
                mode: .inside,
                confidence: 0.90,
                reason: "underground_detected",
                signalSource: .underground
            )
        }

        return nil
    }

    // MARK: - TIER 4: Building Data Classification

    private func classifyWithBuildingData(
        context: DetectionContext,
        buildingDataAvailable: Bool
    ) -> ClassificationResult {
        if !buildingDataAvailable {
            return ClassificationResult(
                mode: .unknown,
                confidence: 0.3,
                reason: "building_data_unavailable",
                signalSource: .fallback
            )
        }

        let motion = context.motion
        let nearestDistance = context.nearestDistance ?? Double.infinity

        // Vehicle detection takes priority
        if motion.isVehicle {
            return ClassificationResult(
                mode: .vehicle,
                confidence: motion.vehicleConfidence,
                signalSource: .motion
            )
        }

        // Inside building polygon is nearly definitive
        if context.insidePolygon != nil {
            return ClassificationResult(
                mode: .inside,
                confidence: 0.98,
                signalSource: .polygon
            )
        }

        // Zone-based classification
        return classifyByZone(
            nearestDistance: nearestDistance,
            motion: motion,
            context: context
        )
    }

    // MARK: - Zone Classification

    private func classifyByZone(
        nearestDistance: Double,
        motion: MotionState,
        context: DetectionContext
    ) -> ClassificationResult {
        if motion.isVehicle {
            return ClassificationResult(
                mode: .vehicle,
                confidence: max(motion.vehicleConfidence, 0.8),
                signalSource: .motion
            )
        }

        // Very close to/inside building
        if nearestDistance < 2 {
            return ClassificationResult(
                mode: .inside,
                confidence: 0.90,
                signalSource: .zone
            )
        }

        // Inside polygon check
        if history.isInsideAnyPolygon() {
            let (isSustained, _) = history.isInsidePolygonSustained()
            let confidence = isSustained ? 0.90 : 0.80
            return ClassificationResult(
                mode: .inside,
                confidence: confidence,
                signalSource: .polygon
            )
        }

        // Zone: Probably inside (0-10m)
        if nearestDistance <= config.zoneProbablyInside {
            if motion.isStationary && !motion.isWalking {
                // Check for near-window scenario
                if context.stationaryDuration > 120 && context.accuracyStats.average < 15 {
                    if nearestDistance < 5 {
                        return ClassificationResult(
                            mode: .inside,
                            confidence: 0.85,
                            reason: "near_window_stationary",
                            signalSource: .zone
                        )
                    }
                }

                // Check for bus stop scenario (not inside polygon + good GPS)
                if !history.isInsideAnyPolygon() && nearestDistance >= 5 && context.accuracyStats.average < 25 {
                    return ClassificationResult(
                        mode: .outside,
                        confidence: 0.75,
                        reason: "outdoor_bus_stop",
                        signalSource: .zone
                    )
                }

                return ClassificationResult(
                    mode: .inside,
                    confidence: 0.80,
                    signalSource: .zone
                )
            }

            if motion.isWalking || motion.isRunning {
                // Check for recent polygon exit
                let (hasExit, _) = history.hasRecentPolygonExit()
                if hasExit {
                    return ClassificationResult(
                        mode: .outside,
                        confidence: 0.90,
                        reason: "recent_polygon_exit",
                        signalSource: .polygon
                    )
                }

                // Walking near building
                let confidence = 0.5 + min(nearestDistance / config.zoneProbablyInside, 1) * 0.15
                return ClassificationResult(
                    mode: .outside,
                    confidence: min(confidence, 0.70),
                    signalSource: .zone
                )
            }

            return ClassificationResult(
                mode: .inside,
                confidence: 0.60,
                signalSource: .zone
            )
        }

        // Zone: Uncertain (10-30m)
        if nearestDistance <= config.zoneProbablyOutside {
            if motion.isWalking || motion.isRunning {
                return ClassificationResult(
                    mode: .outside,
                    confidence: 0.60,
                    signalSource: .zone
                )
            }

            if motion.isVehicle {
                return ClassificationResult(
                    mode: .vehicle,
                    confidence: max(motion.vehicleConfidence, 0.75),
                    signalSource: .motion
                )
            }

            return ClassificationResult(
                mode: .inside,
                confidence: 0.70,
                signalSource: .zone
            )
        }

        // Zone: Probably outside (>40m)
        if nearestDistance > 50 {
            if motion.isVehicle {
                return ClassificationResult(
                    mode: .vehicle,
                    confidence: max(motion.vehicleConfidence, 0.85),
                    signalSource: .motion
                )
            }

            return ClassificationResult(
                mode: .outside,
                confidence: 0.90,
                signalSource: .zone
            )
        }

        // Default: probably outside
        if motion.isVehicle {
            return ClassificationResult(
                mode: .vehicle,
                confidence: max(motion.vehicleConfidence, 0.85),
                signalSource: .motion
            )
        }

        return ClassificationResult(
            mode: .outside,
            confidence: 0.80,
            signalSource: .zone
        )
    }

    // MARK: - Tunnel Detection

    private func checkTunnelDetection(
        currentAccuracy: Double,
        currentMode: LocationMode,
        motion: MotionState
    ) -> LocationMode? {
        // Only check when in vehicle mode
        guard currentMode == .vehicle || motion.isVehicle else {
            if tunnelState.isActive {
                tunnelState.exitTunnel()
            }
            return nil
        }

        // Detect tunnel entry (GPS accuracy degrades significantly while in vehicle)
        if currentAccuracy > 100 && !tunnelState.isActive {
            tunnelState.enterTunnel(mode: currentMode)
            return tunnelState.preTunnelMode ?? .vehicle
        }

        // While in tunnel
        if tunnelState.isActive {
            // Check for expired tunnel mode
            if tunnelState.isExpired(timestamp: Date()) {
                tunnelState.exitTunnel()
                return nil
            }

            // GPS recovered = tunnel exit
            if currentAccuracy < 50 {
                tunnelState.exitTunnel()
                return nil
            }

            // Maintain tunnel mode
            return tunnelState.preTunnelMode ?? .vehicle
        }

        return nil
    }

    // MARK: - Mode Lock

    private func evaluateModeLock(state: DetectionState, context: DetectionContext) {
        // Check if existing lock should be released
        if let lock = modeLock {
            if lock.shouldUnlock(newMode: state.mode, newConfidence: state.confidence, timestamp: Date()) ||
               lock.isExpired(timestamp: Date()) {
                modeLock = nil
            }
        }

        // Check if new lock should be created
        if modeLock == nil && state.confidence >= 0.75 {
            var signalSources: Set<String> = []

            if history.hasRecentFloorDetection() {
                signalSources.insert("floor")
            }
            if context.accuracyStats.sampleCount >= 3 {
                signalSources.insert("accuracyPattern")
            }
            if context.insidePolygon != nil {
                signalSources.insert("polygon")
            }
            if context.motion.isVehicle || context.motion.isWalking {
                signalSources.insert("motion")
            }

            if history.shouldCreateModeLock(
                mode: state.mode,
                confidence: state.confidence,
                signalSources: signalSources,
                nearestBuildingDistance: context.nearestDistance
            ) {
                modeLock = ModeLock(
                    lockedMode: state.mode,
                    lockStartTime: Date(),
                    lockConfidence: state.confidence
                )
            }
        }
    }

    // MARK: - Helper Methods

    private func getGPSAccuracyFactor(_ accuracy: CLLocationAccuracy) -> Double {
        guard accuracy > 0 else { return 1.0 }

        if accuracy <= config.gpsAccuracyPenaltyThreshold {
            return 1.0
        }

        if accuracy >= config.maxGPSAccuracyMeters {
            return 0.5
        }

        let range = config.maxGPSAccuracyMeters - config.gpsAccuracyPenaltyThreshold
        let excess = accuracy - config.gpsAccuracyPenaltyThreshold
        let penalty = (excess / range) * 0.5

        return 1.0 - penalty
    }

    private func getPressureValidation(proposedMode: LocationMode, motion: MotionState) -> Double {
        guard let pressureChange = history.getRecentPressureChange() else {
            return 0
        }

        // Pressure drop agrees with outdoor transition
        if proposedMode == .outside && pressureChange < -2.0 {
            return 0.10
        }

        // Pressure rise agrees with indoor transition
        if proposedMode == .inside && pressureChange > 2.0 {
            return 0.10
        }

        // Small boost for moderate agreement
        if proposedMode == .outside && pressureChange < -1.0 {
            return 0.05
        }
        if proposedMode == .inside && pressureChange > 1.0 {
            return 0.05
        }

        return 0
    }

    private func getStationaryDuration() -> TimeInterval {
        return motionService.getStationaryDuration()
    }

    private func createState(
        mode: LocationMode,
        confidence: Double,
        source: SignalSource,
        reason: String? = nil,
        coordinate: CLLocationCoordinate2D,
        accuracy: Double?,
        speed: Double?,
        motion: MotionState,
        context: DetectionContext? = nil
    ) -> DetectionState {
        DetectionState(
            mode: mode,
            confidence: confidence,
            source: source,
            reason: reason,
            coordinate: coordinate,
            accuracy: accuracy,
            speed: speed,
            activity: motion.activity,
            polygonOccupancyDuration: context?.insidePolygon != nil ? history.getCurrentPolygonDuration() : nil,
            isStationaryNearBuilding: motion.isStationary && (context?.nearestDistance ?? 100) < 40,
            stationaryDuration: getStationaryDuration(),
            nearestBuildingDistance: context?.nearestDistance
        )
    }

    private func createUnknownState(
        coordinate: CLLocationCoordinate2D,
        accuracy: Double,
        reason: String
    ) -> DetectionState {
        DetectionState.unknown(
            coordinate: coordinate,
            accuracy: accuracy > 0 ? accuracy : nil,
            reason: reason
        )
    }
}
