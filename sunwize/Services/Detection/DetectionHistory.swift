import Foundation
import CoreLocation

// MARK: - Detection History

/// Manages historical data for location classification decisions
/// Handles location entries, motion samples, accuracy readings, and drift detection
@MainActor
class DetectionHistory: ObservableObject {

    // MARK: - Configuration

    struct Config {
        let historyWindowSeconds: TimeInterval = 300     // 5 minutes
        let maxLocationEntries: Int = 20
        let maxMotionSamples: Int = 50
        let maxAccuracyReadings: Int = 30
        let maxDriftSamples: Int = 20
        let maxPressureSamples: Int = 20
        let confidenceThresholdForHistory: Double = 0.55
        let minConfidenceForKnownState: Double = 0.60
        let minSamplesForTransition: Int = 2

        static let `default` = Config()
    }

    private let config: Config

    // MARK: - History Storage

    private(set) var locationHistory: [LocationHistoryEntry] = []
    private(set) var motionSamples: [MotionSample] = []
    private(set) var accuracyReadings: [AccuracyReading] = []
    private(set) var driftSamples: [DriftSample] = []
    private(set) var pressureSamples: [PressureSample] = []

    // MARK: - Polygon Tracking

    /// Building IDs currently inside (exact boundary tracking)
    private(set) var currentPolygons: Set<String> = []

    /// Track entry time for sustained occupancy detection
    private(set) var polygonEntryTimestamps: [String: Date] = [:]

    /// Track exit time for recent exit detection
    private(set) var polygonExitTimestamps: [String: Date] = [:]

    /// Track entry position to validate actual movement at exit
    private(set) var polygonEntryPositions: [String: CLLocationCoordinate2D] = [:]

    /// Geofence entry timestamps (for circular geofence background wake-up)
    private(set) var geofenceEntryTimestamps: [String: Date] = [:]

    /// Last geofence exit timestamp
    private(set) var geofenceExitTimestamp: Date?

    // MARK: - Recent State Tracking

    /// Timestamp of last high-confidence inside detection (polygon)
    private(set) var lastHighConfidenceInsideTimestamp: Date?

    /// Last floor detection timestamp
    private(set) var lastFloorDetectionTime: Date?

    /// Last known floor level
    private(set) var lastKnownFloor: Int?

    // MARK: - Persistence

    private lazy var persistenceDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DetectionHistory", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("DetectionHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }()

    private lazy var locationHistoryURL = persistenceDirectory.appendingPathComponent("locationHistory.json")
    private lazy var motionHistoryURL = persistenceDirectory.appendingPathComponent("motionHistory.json")
    private lazy var accuracyHistoryURL = persistenceDirectory.appendingPathComponent("accuracyHistory.json")

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
        loadPersistedData()
    }

    // MARK: - Location History Management

    /// Add a location entry to history
    func addLocationEntry(_ entry: LocationHistoryEntry) {
        guard entry.mode != .unknown else { return }

        locationHistory.append(entry)
        pruneLocationHistory()
        saveLocationHistory()
    }

    /// Add a location entry from a detection state
    func addLocationEntry(from state: DetectionState, signalSource: SignalSource) {
        let entry = LocationHistoryEntry(
            timestamp: state.timestamp,
            mode: state.mode,
            confidence: state.confidence,
            latitude: state.latitude,
            longitude: state.longitude,
            accuracy: state.accuracy,
            uncertaintyReason: nil,
            signalSource: signalSource.rawValue
        )
        addLocationEntry(entry)
    }

    private func pruneLocationHistory() {
        let now = Date()
        locationHistory = Array(locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= config.historyWindowSeconds
        }.suffix(config.maxLocationEntries))
    }

    // MARK: - Motion Sample Management

    /// Add a motion sample
    func addMotionSample(_ sample: MotionSample) {
        motionSamples.append(sample)
        pruneMotionSamples()
        saveMotionHistory()
    }

    private func pruneMotionSamples() {
        let now = Date()
        motionSamples = Array(motionSamples.filter {
            now.timeIntervalSince($0.timestamp) <= 600 // 10 minutes
        }.suffix(config.maxMotionSamples))
    }

    // MARK: - Accuracy Reading Management

    /// Add an accuracy reading
    func addAccuracyReading(_ reading: AccuracyReading) {
        accuracyReadings.append(reading)

        // Keep last 30 samples (2-5 minutes of data)
        if accuracyReadings.count > config.maxAccuracyReadings {
            accuracyReadings.removeFirst()
        }

        // Persist every 5 readings to avoid excessive disk writes
        if accuracyReadings.count % 5 == 0 {
            saveAccuracyHistory()
        }
    }

    /// Add an accuracy reading from a location
    func addAccuracyReading(from location: CLLocation) {
        let reading = AccuracyReading(
            timestamp: Date(),
            accuracy: location.horizontalAccuracy,
            coordinate: location.coordinate
        )
        addAccuracyReading(reading)
    }

    /// Get accuracy statistics from recent readings
    func getAccuracyStatistics() -> AccuracyStats {
        guard accuracyReadings.count >= 5 else {
            return .empty
        }

        let recentAccuracies = accuracyReadings.suffix(10).map { $0.accuracy }
        let average = recentAccuracies.average
        let stdDev = recentAccuracies.standardDeviation

        return AccuracyStats(
            average: average,
            stdDev: stdDev,
            sampleCount: recentAccuracies.count
        )
    }

    /// Check for sustained excellent GPS accuracy (fast-path outdoor detection)
    /// Returns whether we have sustained excellent GPS, average accuracy, and duration
    func checkSustainedExcellentGPS() -> (hasExcellent: Bool, avgAccuracy: Double, duration: TimeInterval) {
        let now = Date()

        // Filter to readings within last 60 seconds with excellent accuracy (<15m)
        let recentExcellent = accuracyReadings.filter {
            now.timeIntervalSince($0.timestamp) <= 60 && $0.accuracy < 15
        }

        // Need at least 3 excellent readings
        guard recentExcellent.count >= 3 else {
            return (false, 0, 0)
        }

        let avgAccuracy = recentExcellent.map { $0.accuracy }.average

        // Calculate duration from first to last excellent reading
        let sortedByTime = recentExcellent.sorted { $0.timestamp < $1.timestamp }
        let duration: TimeInterval
        if let first = sortedByTime.first, let last = sortedByTime.last {
            duration = last.timestamp.timeIntervalSince(first.timestamp)
        } else {
            duration = 0
        }

        // Sustained excellent GPS requires average < 12m
        let hasExcellent = avgAccuracy < 12

        return (hasExcellent, avgAccuracy, duration)
    }

    // MARK: - Pressure Sample Management

    /// Add a pressure sample
    func addPressureSample(_ sample: PressureSample) {
        pressureSamples.append(sample)

        // Keep last 20 samples (1-2 minutes of data)
        if pressureSamples.count > config.maxPressureSamples {
            pressureSamples.removeFirst()
        }
    }

    /// Clear pressure history (called when resetting baseline)
    func clearPressureHistory() {
        pressureSamples.removeAll()
    }

    /// Get recent pressure change
    func getRecentPressureChange() -> Double? {
        guard pressureSamples.count >= 3 else { return nil }

        let recent = Array(pressureSamples.suffix(5))
        guard let oldest = recent.first, let newest = recent.last else { return nil }

        return newest.relativeAltitude - oldest.relativeAltitude
    }

    // MARK: - Drift Detection

    /// Add a drift sample and check for GPS drift patterns
    func addDriftSample(_ sample: DriftSample) {
        driftSamples.append(sample)

        // Keep last 5 minutes of samples
        let now = Date()
        driftSamples = driftSamples.filter {
            now.timeIntervalSince($0.timestamp) <= 300
        }

        // Limit to max samples
        if driftSamples.count > config.maxDriftSamples {
            driftSamples.removeFirst()
        }
    }

    /// Detect GPS drift patterns
    /// Returns drift analysis with recommended mode to maintain
    func detectGPSDrift(
        newMode: LocationMode,
        coordinate: CLLocationCoordinate2D,
        confidence: Double,
        isStationary: Bool
    ) -> (isDrifting: Bool, recommendedMode: LocationMode, confidence: Double)? {

        // Only check for drift when stationary (drift happens when not moving)
        guard isStationary else { return nil }

        // Add current reading to drift detection history
        let sample = DriftSample(
            timestamp: Date(),
            mode: newMode,
            coordinate: coordinate,
            confidence: confidence
        )
        addDriftSample(sample)

        // Need at least 6 samples (3+ minutes of data)
        guard driftSamples.count >= 6 else { return nil }

        // Analyze recent samples for oscillation pattern
        let recentSamples = Array(driftSamples.suffix(6))
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
        let hasOscillations = oscillations >= 3
        let hasHighVariance = avgMovement > 8.0
        let noFloorChanges = lastFloorDetectionTime == nil ||
                             Date().timeIntervalSince(lastFloorDetectionTime!) > 60

        if hasOscillations && hasHighVariance && noFloorChanges {
            // Determine mode to lock to using most frequent mode in recent history
            var modeCounts: [LocationMode: Int] = [:]
            for mode in modes where mode != .unknown {
                modeCounts[mode, default: 0] += 1
            }

            if let mostFrequent = modeCounts.max(by: { $0.value < $1.value }) {
                return (isDrifting: true, recommendedMode: mostFrequent.key, confidence: 0.60)
            }

            // Fallback: mark as unknown
            return (isDrifting: true, recommendedMode: .unknown, confidence: 0.0)
        }

        // No drift detected
        return nil
    }

    // MARK: - Polygon Occupancy

    /// Update polygon occupancy tracking
    func updatePolygonOccupancy(
        coordinate: CLLocationCoordinate2D,
        buildings: [OverpassBuilding]
    ) {
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

    private func handlePolygonEntry(buildingId: String, coordinate: CLLocationCoordinate2D) {
        let now = Date()
        polygonEntryTimestamps[buildingId] = now
        polygonEntryPositions[buildingId] = coordinate
    }

    private func handlePolygonExit(buildingId: String, coordinate: CLLocationCoordinate2D) {
        let now = Date()

        // MOVEMENT VALIDATION: Check if user actually moved or if this is GPS drift
        if let entryPosition = polygonEntryPositions[buildingId] {
            let movementDistance = haversineDistance(from: entryPosition, to: coordinate)

            if movementDistance < 10 {
                // Position barely changed (<10m) - likely GPS drift, not actual exit
                return
            }
        }

        // Valid exit - record timestamp
        polygonExitTimestamps[buildingId] = now
        polygonEntryTimestamps.removeValue(forKey: buildingId)
        polygonEntryPositions.removeValue(forKey: buildingId)
    }

    /// Check if currently inside any building polygon
    func isInsideAnyPolygon() -> Bool {
        return !currentPolygons.isEmpty
    }

    /// Check if sustained inside polygon (>30 seconds)
    func isInsidePolygonSustained(thresholdSeconds: TimeInterval = 30) -> (Bool, TimeInterval?) {
        guard let currentBuildingId = currentPolygons.first,
              let entryTime = polygonEntryTimestamps[currentBuildingId] else {
            return (false, nil)
        }

        let duration = Date().timeIntervalSince(entryTime)
        return (duration > thresholdSeconds, duration)
    }

    /// Check if recently exited polygon (within specified seconds)
    func hasRecentPolygonExit(withinSeconds: TimeInterval = 90) -> (Bool, TimeInterval?) {
        let now = Date()

        let recentExits = polygonExitTimestamps.values.compactMap { exitTime -> TimeInterval? in
            let timeSinceExit = now.timeIntervalSince(exitTime)
            return timeSinceExit < withinSeconds ? timeSinceExit : nil
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

    /// Get the building we're currently inside (if any)
    func getCurrentPolygonBuildingId() -> String? {
        return currentPolygons.first
    }

    // MARK: - Floor Detection

    /// Record floor detection
    func recordFloorDetection(level: Int) {
        lastFloorDetectionTime = Date()
        lastKnownFloor = level
    }

    /// Check if floor was detected recently
    func hasRecentFloorDetection(withinSeconds: TimeInterval = 300) -> Bool {
        guard let lastFloorTime = lastFloorDetectionTime else {
            return false
        }
        return Date().timeIntervalSince(lastFloorTime) < withinSeconds
    }

    // MARK: - Geofence Tracking

    /// Record circular geofence entry
    func recordGeofenceEntry(regionId: String) {
        geofenceEntryTimestamps[regionId] = Date()
    }

    /// Record circular geofence exit
    func recordGeofenceExit(regionId: String) {
        geofenceExitTimestamp = Date()
        geofenceEntryTimestamps.removeValue(forKey: regionId)
    }

    /// Get time spent in geofence
    func getTimeInGeofence(regionId: String) -> TimeInterval? {
        guard let entryTime = geofenceEntryTimestamps[regionId] else { return nil }
        return Date().timeIntervalSince(entryTime)
    }

    // MARK: - High Confidence Tracking

    /// Record high confidence inside detection
    func recordHighConfidenceInside() {
        lastHighConfidenceInsideTimestamp = Date()
    }

    /// Check if recently had high confidence inside detection
    func hasRecentHighConfidenceInside(withinSeconds: TimeInterval = 30) -> Bool {
        guard let timestamp = lastHighConfidenceInsideTimestamp else { return false }
        return Date().timeIntervalSince(timestamp) < withinSeconds
    }

    /// Clear high confidence inside protection
    func clearHighConfidenceInsideProtection() {
        lastHighConfidenceInsideTimestamp = nil
    }

    // MARK: - Stable Mode Detection

    /// Get stable mode from history using weighted voting
    func getStableModeFromHistory(
        allowSingleSample: Bool = false,
        isStationary: Bool
    ) -> LocationMode? {
        let now = Date()

        // Adaptive history window based on motion state
        let recentWindow: TimeInterval = isStationary ? 60 : 120

        let recentReadings = locationHistory.filter {
            now.timeIntervalSince($0.timestamp) <= recentWindow &&
            $0.confidence >= config.confidenceThresholdForHistory &&
            $0.mode != .unknown
        }

        // Check if latest reading is inside polygon (near-definitive)
        if let latest = recentReadings.last,
           latest.mode == .inside,
           latest.confidence >= 0.95 {
            recordHighConfidenceInside()

            // Clear low-confidence outdoor history
            locationHistory.removeAll { entry in
                entry.mode == .outside &&
                now.timeIntervalSince(entry.timestamp) < 90 &&
                entry.confidence < 0.85
            }

            return .inside
        }

        // Require minimum samples for transition
        guard recentReadings.count >= config.minSamplesForTransition else {
            if allowSingleSample && recentReadings.count == 1 {
                let reading = recentReadings[0]
                if reading.mode == .vehicle {
                    return reading.mode
                } else if reading.mode == .outside && reading.confidence >= 0.80 {
                    return reading.mode
                }
            }
            return nil
        }

        // Try consecutive samples first (fastest path for stable states)
        let lastNSamples = Array(recentReadings.suffix(config.minSamplesForTransition))
        let firstMode = lastNSamples[0].mode

        if lastNSamples.allSatisfy({ $0.mode == firstMode }) {
            return firstMode
        }

        // Check for recent high-confidence inside protection
        if hasRecentHighConfidenceInside() {
            let hasRecentInsideEvidence = recentReadings.contains { reading in
                reading.mode == .inside &&
                now.timeIntervalSince(reading.timestamp) < 15 &&
                reading.confidence >= 0.50
            }

            if hasRecentInsideEvidence {
                return .inside
            } else {
                clearHighConfidenceInsideProtection()
            }
        }

        // Need at least 4 samples for weighted voting
        guard recentReadings.count >= 4 else {
            return nil
        }

        // Use confidence-weighted voting with signal quality decay
        var votes: [LocationMode: Double] = [:]

        for reading in recentReadings {
            let age = now.timeIntervalSince(reading.timestamp)
            let effectiveHalfLife = 60.0 * reading.signalQualityWeight
            let decayFactor = exp(-age / effectiveHalfLife)
            let weight = reading.confidence * decayFactor
            votes[reading.mode, default: 0.0] += weight
        }

        // Apply streak bonus
        let streak = getConsecutiveModeStreak()
        if streak.count >= 3 && streak.mode != .unknown {
            let streakBonus = min(Double(streak.count) * 0.04, 0.20)
            votes[streak.mode, default: 0.0] += streakBonus
        }

        guard let (winningMode, winningScore) = votes.max(by: { $0.value < $1.value }) else {
            return nil
        }

        // Require strong margin to prevent GPS drift dominance
        let sortedVotes = votes.sorted { $0.value > $1.value }
        if sortedVotes.count > 1 {
            let secondScore = sortedVotes[1].value
            if winningScore < secondScore * 2.5 {
                return nil
            }
        }

        // Check for very recent high-confidence inside reading
        if let mostRecentInside = recentReadings.last(where: { $0.mode == .inside && $0.confidence >= 0.95 }),
           now.timeIntervalSince(mostRecentInside.timestamp) < 10 {
            return .inside
        }

        return winningMode
    }

    /// Get consecutive mode streak from recent history
    func getConsecutiveModeStreak() -> (mode: LocationMode, count: Int, avgConfidence: Double) {
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

    // MARK: - Mode Lock Evaluation

    /// Check if current state warrants creating a mode lock
    func shouldCreateModeLock(
        mode: LocationMode,
        confidence: Double,
        signalSources: Set<String>,
        nearestBuildingDistance: Double?
    ) -> Bool {
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

        // Require at least 2 different signal sources
        guard signalSources.count >= 2 else { return false }

        // If within 30m of building, require stronger validation
        if let distance = nearestBuildingDistance, distance <= 30 {
            let hasStrongValidation = signalSources.contains("floor") ||
                                      signalSources.contains("polygon") ||
                                      signalSources.contains("geofence")
            if !hasStrongValidation {
                return false
            }
        }

        return true
    }

    // MARK: - Clear Methods

    /// Clear all history
    func clearAllHistory() {
        locationHistory.removeAll()
        motionSamples.removeAll()
        accuracyReadings.removeAll()
        driftSamples.removeAll()
        pressureSamples.removeAll()
        currentPolygons.removeAll()
        polygonEntryTimestamps.removeAll()
        polygonExitTimestamps.removeAll()
        polygonEntryPositions.removeAll()
        geofenceEntryTimestamps.removeAll()
        geofenceExitTimestamp = nil
        lastHighConfidenceInsideTimestamp = nil
        lastFloorDetectionTime = nil
        lastKnownFloor = nil

        saveLocationHistory()
        saveMotionHistory()
    }

    // MARK: - Persistence

    private func loadPersistedData() {
        loadLocationHistory()
        loadMotionHistory()
        loadAccuracyHistory()
    }

    private func loadLocationHistory() {
        guard let data = try? Data(contentsOf: locationHistoryURL) else { return }
        let decoder = JSONDecoder()
        if let entries = try? decoder.decode([LocationHistoryEntry].self, from: data) {
            locationHistory = entries
            pruneLocationHistory()
        }
    }

    private func loadMotionHistory() {
        guard let data = try? Data(contentsOf: motionHistoryURL) else { return }
        let decoder = JSONDecoder()
        if let samples = try? decoder.decode([MotionSample].self, from: data) {
            motionSamples = samples
            pruneMotionSamples()
        }
    }

    private func saveLocationHistory() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(locationHistory) else { return }
        try? data.write(to: locationHistoryURL, options: .atomic)
    }

    private func saveMotionHistory() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(motionSamples) else { return }
        try? data.write(to: motionHistoryURL, options: .atomic)
    }

    private func loadAccuracyHistory() {
        guard let data = try? Data(contentsOf: accuracyHistoryURL) else { return }
        let decoder = JSONDecoder()
        if let readings = try? decoder.decode([AccuracyReading].self, from: data) {
            accuracyReadings = readings
            // Prune old readings (keep last 5 minutes worth)
            let now = Date()
            accuracyReadings = accuracyReadings.filter { now.timeIntervalSince($0.timestamp) <= 300 }
        }
    }

    private func saveAccuracyHistory() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(accuracyReadings) else { return }
        try? data.write(to: accuracyHistoryURL, options: .atomic)
    }

    // MARK: - Utility

    private func haversineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        return GeometryUtils.haversineDistance(
            lat1: from.latitude,
            lon1: from.longitude,
            lat2: to.latitude,
            lon2: to.longitude
        )
    }
}
