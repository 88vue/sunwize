import Foundation
import CoreMotion
import CoreLocation

// MARK: - Motion Service

/// Service for CoreMotion activity monitoring and vehicle detection
/// Handles motion sample collection, vehicle persistence, and activity analysis
@MainActor
class MotionService: ObservableObject {
    static let shared = MotionService()

    // MARK: - Configuration

    private let config = DetectionConfig.default

    // MARK: - Core Motion

    private let motionManager = CMMotionActivityManager()
    private var isMonitoring = false

    // MARK: - Motion History

    private var motionSamples: [MotionSample] = []

    // MARK: - Vehicle Persistence State

    /// Last time vehicle mode was detected
    private(set) var lastVehicleDetectionTime: Date?

    /// Time when vehicle mode was confirmed
    private(set) var vehicleModeConfirmedTime: Date?

    /// Last strong vehicle confidence value
    private(set) var lastStrongVehicleConfidence: Double = 0.0

    /// Count of consecutive stops (for stop-and-go detection)
    private(set) var consecutiveStops: Int = 0

    /// Last significant speed (>2 m/s)
    private(set) var lastSignificantSpeed: Double = 0.0

    /// Whether currently in sticky vehicle mode
    private(set) var isInVehicleMode: Bool = false

    // MARK: - Stationary Duration Tracking

    /// Time when user became stationary
    private var stationaryStartTime: Date?

    // MARK: - Current Speed (from GPS)

    private var currentSpeed: Double = 0

    // MARK: - Callbacks

    /// Called when motion activity changes significantly
    var onSignificantMotionChange: ((MotionActivity, MotionActivity) -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Start motion activity monitoring
    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("[MotionService] Motion activity not available on this device")
            return
        }

        guard !isMonitoring else { return }

        motionManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            Task { @MainActor in
                self.handleMotionActivity(activity)
            }
        }

        isMonitoring = true
        print("[MotionService] Motion monitoring started")
    }

    /// Stop motion activity monitoring
    func stopMonitoring() {
        motionManager.stopActivityUpdates()
        isMonitoring = false
        print("[MotionService] Motion monitoring stopped")
    }

    /// Update current speed from GPS location
    func updateSpeed(_ speed: Double) {
        currentSpeed = max(0, speed)

        // Add motion sample with current activity
        let sample = MotionSample(
            timestamp: Date(),
            speed: currentSpeed,
            activity: motionSamples.last?.activity ?? .unknown
        )
        addMotionSample(sample)
    }

    /// Add a motion sample
    func addMotionSample(_ sample: MotionSample) {
        motionSamples.append(sample)
        pruneMotionHistory()

        // Track last significant speed
        if sample.speed > 2.0 {
            lastSignificantSpeed = sample.speed
        }
    }

    /// Analyze current motion state
    func analyzeMotion() -> MotionState {
        let now = Date()
        let recentMotion = motionSamples.filter {
            now.timeIntervalSince($0.timestamp) <= 60
        }

        guard !recentMotion.isEmpty else {
            return .unknown
        }

        // Calculate average speed
        let avgSpeed = recentMotion.reduce(0.0) { $0 + $1.speed } / Double(recentMotion.count)

        // Check recent activities from CoreMotion
        let activities = recentMotion.map { $0.activity }
        let hasVehicleActivity = activities.contains(.automotive)
        let hasWalkingActivity = activities.contains(.walking)
        let hasRunningActivity = activities.contains(.running)
        let hasCyclingActivity = activities.contains(.cycling)
        let isStationary = avgSpeed < config.stationarySpeedThresholdMS

        // Check if just started moving
        let justStartedMoving = checkJustStartedMoving()

        // Analyze vehicle detection
        let vehicleAnalysis = analyzeVehicleDetection(
            recentMotion: recentMotion,
            avgSpeed: avgSpeed,
            hasVehicleActivity: hasVehicleActivity,
            hasCyclingActivity: hasCyclingActivity,
            hasWalkingActivity: hasWalkingActivity,
            hasRunningActivity: hasRunningActivity
        )

        return MotionState(
            isStationary: isStationary,
            isWalking: hasWalkingActivity || (avgSpeed > 0.5 && avgSpeed < 2.0),
            isRunning: hasRunningActivity || (avgSpeed > 2.0 && avgSpeed < 5.0),
            isVehicle: vehicleAnalysis.isVehicle,
            justStartedMoving: justStartedMoving,
            activity: activities.last,
            averageSpeed: avgSpeed,
            vehicleConfidence: vehicleAnalysis.confidence
        )
    }

    /// Get vehicle analysis result
    func getVehicleAnalysis() -> VehicleAnalysis {
        let state = analyzeMotion()
        return VehicleAnalysis(
            isVehicle: state.isVehicle,
            confidence: state.vehicleConfidence,
            reason: state.isVehicle ? "motion_analysis" : "no_vehicle_evidence",
            isPersisted: isInVehicleMode && lastVehicleDetectionTime != nil
        )
    }

    /// Reset vehicle mode (called when parking detected)
    func resetVehicleMode() {
        isInVehicleMode = false
        lastVehicleDetectionTime = nil
        vehicleModeConfirmedTime = nil
        consecutiveStops = 0
        lastStrongVehicleConfidence = 0.0
        print("[MotionService] Vehicle mode reset")
    }

    /// Get duration user has been stationary
    /// Returns 0 if user is not currently stationary
    func getStationaryDuration() -> TimeInterval {
        let motion = analyzeMotion()

        if motion.isStationary {
            // User is stationary - track or return duration
            if stationaryStartTime == nil {
                stationaryStartTime = Date()
                return 0
            }
            return Date().timeIntervalSince(stationaryStartTime!)
        } else {
            // User is moving - reset stationary tracking
            stationaryStartTime = nil
            return 0
        }
    }

    /// Clear all motion history
    func clearHistory() {
        motionSamples.removeAll()
        resetVehicleMode()
    }

    // MARK: - Private Methods

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        let motionActivity = MotionActivity(from: activity)
        let previousActivity = motionSamples.last?.activity ?? .unknown

        // Create and add sample
        let sample = MotionSample(
            timestamp: Date(),
            speed: currentSpeed,
            activity: motionActivity
        )
        addMotionSample(sample)

        // Check for significant activity changes
        let wasAutomotive = previousActivity == .automotive
        let isNowAutomotive = motionActivity == .automotive

        let wasStationary = previousActivity == .stationary
        let isNowMoving = motionActivity == .walking || motionActivity == .running

        if (wasAutomotive && !isNowAutomotive) || (wasStationary && isNowMoving) {
            onSignificantMotionChange?(previousActivity, motionActivity)
        }
    }

    private func pruneMotionHistory() {
        let now = Date()
        motionSamples = Array(motionSamples.filter {
            now.timeIntervalSince($0.timestamp) <= 600 // 10 minutes
        }.suffix(50))
    }

    private func checkJustStartedMoving() -> Bool {
        let now = Date()
        let last30Seconds = motionSamples.filter {
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

    // MARK: - Vehicle Detection

    private func analyzeVehicleDetection(
        recentMotion: [MotionSample],
        avgSpeed: Double,
        hasVehicleActivity: Bool,
        hasCyclingActivity: Bool,
        hasWalkingActivity: Bool,
        hasRunningActivity: Bool
    ) -> (isVehicle: Bool, confidence: Double) {

        let now = Date()
        let activities = recentMotion.map { $0.activity }
        var vehicleConfidence = 0.0

        // TIER 0: Check vehicle mode persistence (stop-and-go support)
        if let lastVehicleTime = lastVehicleDetectionTime {
            let timeSinceVehicle = now.timeIntervalSince(lastVehicleTime)

            // PARKING DETECTION: Exit vehicle mode after 5+ minutes stationary with no automotive
            if timeSinceVehicle > 300 && avgSpeed < 0.5 && !hasVehicleActivity {
                print("[MotionService] PARKING detected: 5+ min stationary - exiting vehicle mode")
                resetVehicleMode()
            }
            // Maintain vehicle mode for up to 5 minutes after last detection
            else if timeSinceVehicle <= 300 && lastStrongVehicleConfidence >= 0.85 {
                let isStopAndGo = avgSpeed < 2.0 && lastSignificantSpeed > 5.0

                if isStopAndGo {
                    consecutiveStops += 1
                }

                // Maintain high confidence with slower decay (600s half-life)
                vehicleConfidence = max(0.85, lastStrongVehicleConfidence - (timeSinceVehicle / 600.0))
            }
        }

        // TIER 1: CoreMotion automotive activity (HIGHEST PRIORITY)
        if hasVehicleActivity {
            let automotiveCount = activities.filter { $0 == .automotive }.count
            let automotiveRatio = Double(automotiveCount) / Double(activities.count)

            if automotiveRatio > 0.5 {
                // 50%+ automotive samples = definitely in vehicle
                vehicleConfidence = max(vehicleConfidence, 0.95)
                updateVehicleState(confidence: 0.95)
            } else if avgSpeed > 3.0 {
                // Automotive activity + moderate speed = vehicle
                vehicleConfidence = max(vehicleConfidence, 0.90)
                updateVehicleState(confidence: 0.90)
            } else {
                // Automotive activity even when stopped
                vehicleConfidence = max(vehicleConfidence, 0.85)
                updateVehicleState(confidence: 0.85)
            }
        }

        // TIER 2: GPS speed-based detection
        let last10Seconds = Array(recentMotion.suffix(3))
        if last10Seconds.count >= 3 && vehicleConfidence < 0.95 {
            let sustainedSpeeds = last10Seconds.map { $0.speed }
            let minSpeed = sustainedSpeeds.min() ?? 0
            let maxSpeed = sustainedSpeeds.max() ?? 0
            let avgSustainedSpeed = sustainedSpeeds.reduce(0.0, +) / Double(sustainedSpeeds.count)

            // Calculate speed variance for cyclist exclusion
            let speedVariance = sustainedSpeeds.map { pow($0 - avgSustainedSpeed, 2) }.reduce(0.0, +) / Double(sustainedSpeeds.count)
            let speedStdDev = sqrt(speedVariance)

            // Highway driving (>50 mph)
            if avgSustainedSpeed > 22.0 {
                vehicleConfidence = max(vehicleConfidence, 0.98)
                updateVehicleState(confidence: 0.98)
            }
            // Fast city driving (25+ mph)
            else if avgSustainedSpeed > 11.0 && minSpeed > 5.0 {
                vehicleConfidence = max(vehicleConfidence, 0.92)
                updateVehicleState(confidence: 0.92)
            }
            // City driving with moderate speed
            else if avgSustainedSpeed > 6.0 && maxSpeed > 8.0 {
                // Cyclist exclusion
                if !isCyclistPattern(
                    hasCycling: hasCyclingActivity,
                    hasRunning: hasRunningActivity,
                    hasVehicle: hasVehicleActivity,
                    avgSpeed: avgSustainedSpeed,
                    speedStdDev: speedStdDev,
                    varianceThreshold: 1.5
                ) {
                    vehicleConfidence = max(vehicleConfidence, 0.88)
                    updateVehicleState(confidence: 0.88)
                }
            }
            // Slow city driving (9+ mph)
            else if avgSustainedSpeed > 4.0 && maxSpeed > 6.0 {
                // Cyclist exclusion
                if !isCyclistPattern(
                    hasCycling: hasCyclingActivity,
                    hasRunning: hasRunningActivity,
                    hasVehicle: hasVehicleActivity,
                    avgSpeed: avgSustainedSpeed,
                    speedStdDev: speedStdDev,
                    varianceThreshold: 1.2
                ) {
                    vehicleConfidence = max(vehicleConfidence, 0.82)
                    updateVehicleState(confidence: 0.82)
                }
            }
        }

        // TIER 2.5: Very slow vehicle detection (parking garage, heavy traffic)
        if vehicleConfidence < 0.80 && hasVehicleActivity && !hasWalkingActivity {
            if avgSpeed > 0.3 && avgSpeed < 4.0 {
                vehicleConfidence = max(vehicleConfidence, 0.78)
                updateVehicleState(confidence: 0.78)
            }
        }

        // TIER 3: Stop-and-go pattern detection
        if vehicleConfidence < 0.85 && recentMotion.count >= 5 {
            let last30Seconds = Array(recentMotion.suffix(10))
            let speeds = last30Seconds.map { $0.speed }

            let avgSpeed30s = speeds.reduce(0.0, +) / Double(speeds.count)
            let speedVariance = speeds.map { pow($0 - avgSpeed30s, 2) }.reduce(0.0, +) / Double(speeds.count)
            let speedStdDev = sqrt(speedVariance)

            // High variance + moderate speeds = stop-and-go traffic
            if speedStdDev > 2.5 && avgSpeed30s > 3.0 && (speeds.max() ?? 0) > 8.0 {
                vehicleConfidence = max(vehicleConfidence, 0.85)
                updateVehicleState(confidence: 0.85)
            }
        }

        // Threshold check (aligned with BackgroundTaskManager 0.85 threshold)
        let isVehicle = vehicleConfidence > 0.85

        return (isVehicle, vehicleConfidence)
    }

    private func isCyclistPattern(
        hasCycling: Bool,
        hasRunning: Bool,
        hasVehicle: Bool,
        avgSpeed: Double,
        speedStdDev: Double,
        varianceThreshold: Double
    ) -> Bool {
        // Cyclist indicators:
        // 1. Cycling activity
        // 2. Running at high speed (misclassified cyclist)
        // 3. Low speed variance without vehicle activity
        let hasRunningWithHighSpeed = hasRunning && avgSpeed > 4.0
        let hasLowSpeedVariance = speedStdDev < varianceThreshold

        return hasCycling || hasRunningWithHighSpeed || (hasLowSpeedVariance && !hasVehicle)
    }

    private func updateVehicleState(confidence: Double) {
        lastVehicleDetectionTime = Date()
        lastStrongVehicleConfidence = confidence
        isInVehicleMode = true
    }
}
