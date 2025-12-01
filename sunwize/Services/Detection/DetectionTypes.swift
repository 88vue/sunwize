import Foundation
import CoreLocation
import CoreMotion

// MARK: - Location Mode

/// The current detected location mode of the user
enum LocationMode: String, Codable, CaseIterable {
    case inside
    case outside
    case vehicle
    case unknown

    var emoji: String {
        switch self {
        case .inside: return "🏠"
        case .outside: return "🌳"
        case .vehicle: return "🚗"
        case .unknown: return "❓"
        }
    }
}

// MARK: - Motion Activity

/// Motion activity types detected by CoreMotion
enum MotionActivity: String, Codable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown

    init(from cmActivity: CMMotionActivity?) {
        guard let activity = cmActivity else {
            self = .unknown
            return
        }

        if activity.automotive {
            self = .automotive
        } else if activity.cycling {
            self = .cycling
        } else if activity.running {
            self = .running
        } else if activity.walking {
            self = .walking
        } else if activity.stationary {
            self = .stationary
        } else {
            self = .unknown
        }
    }
}

// MARK: - Signal Source

/// The source of a location classification signal
enum SignalSource: String, Codable {
    case floor              // CLFloor detection (multi-story building)
    case accuracyPattern    // GPS accuracy pattern analysis
    case polygon            // Inside OSM building polygon
    case zone               // Distance-based zone classification
    case motion             // CoreMotion vehicle/activity detection
    case geofence           // Circular geofence entry/exit
    case fallback           // Insufficient evidence, default classification
    case manualOverride     // User-initiated manual indoor override
    case tunnel             // Tunnel detection (GPS degradation while driving)
    case driftLock          // GPS drift detected, locked to stable mode
    case underground        // Underground detection via pressure
    case parallelWalking    // Parallel walking along building face (sidewalk)
}

// MARK: - Location Uncertainty Reason

/// Reasons why location classification may be uncertain
enum LocationUncertaintyReason: String, Codable {
    case insufficientEvidence
    case conflictingSignals
    case gpsUnavailable
    case motionDataUnavailable
    case inStartupPhase
    case poorGPS
    case nearWindow
    case urbanCanyon
    case recentPolygonExit
    case manualOverride
    case tunnel
    case underground
}

// MARK: - Location History Entry

/// A historical record of a location classification
struct LocationHistoryEntry: Codable {
    let timestamp: Date
    let mode: LocationMode
    let confidence: Double
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let uncertaintyReason: LocationUncertaintyReason?
    let signalSource: String?

    /// Weight factor based on signal quality for weighted voting
    var signalQualityWeight: Double {
        guard let source = signalSource, let signalType = SignalSource(rawValue: source) else {
            return 0.5
        }
        switch signalType {
        case .floor: return 2.0           // Definitive indoor signal
        case .polygon: return 1.5         // Strong boundary detection
        case .accuracyPattern: return 1.0 // Good GPS signature
        case .motion: return 0.9          // CoreMotion detection
        case .zone: return 0.8            // Distance-based
        case .geofence: return 0.85       // iOS system geofence
        case .parallelWalking: return 0.75
        case .underground: return 1.2
        case .tunnel: return 1.0
        case .driftLock: return 0.6       // Lower weight for drift lock
        case .manualOverride: return 2.0  // User explicitly set
        case .fallback: return 0.5        // Lowest confidence
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Motion Sample

/// A sample of motion data from CoreMotion
struct MotionSample: Codable {
    let timestamp: Date
    let speed: Double
    let activity: MotionActivity

    var isAutomotive: Bool { activity == .automotive }
    var isCycling: Bool { activity == .cycling }
    var isStationary: Bool { activity == .stationary }
    var isWalking: Bool { activity == .walking }
    var isRunning: Bool { activity == .running }

    init(timestamp: Date, speed: Double, activity: MotionActivity) {
        self.timestamp = timestamp
        self.speed = speed
        self.activity = activity
    }

    init(timestamp: Date, speed: Double, cmActivity: CMMotionActivity?) {
        self.timestamp = timestamp
        self.speed = speed
        self.activity = MotionActivity(from: cmActivity)
    }
}

// MARK: - Speed Sample

/// A sample of speed data for vehicle detection
struct SpeedSample: Codable {
    let timestamp: Date
    let speed: Double
}

// MARK: - Drift Sample

/// A sample for GPS drift detection
struct DriftSample: Codable {
    let timestamp: Date
    let mode: LocationMode
    let coordinate: CLLocationCoordinate2D
    let confidence: Double
}

// MARK: - Accuracy Reading

/// A GPS accuracy reading for pattern analysis
struct AccuracyReading: Codable {
    let timestamp: Date
    let accuracy: Double
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Accuracy Stats

/// Statistics calculated from accuracy history
struct AccuracyStats {
    let average: Double
    let stdDev: Double
    let sampleCount: Int

    static let empty = AccuracyStats(average: 0, stdDev: 0, sampleCount: 0)
}

// MARK: - Pressure Sample

/// A barometric pressure sample for underground/floor detection
struct PressureSample: Codable {
    let timestamp: Date
    let pressure: Double
    let relativeAltitude: Double
}

// MARK: - Classification Result

/// The result of a classification signal evaluation
struct ClassificationResult {
    let mode: LocationMode
    let confidence: Double
    let reason: String?
    let signalSource: SignalSource

    init(mode: LocationMode, confidence: Double, reason: String? = nil, signalSource: SignalSource) {
        self.mode = mode
        self.confidence = confidence
        self.reason = reason
        self.signalSource = signalSource
    }
}

// MARK: - Mode Lock

/// A lock on a detected mode to prevent flip-flopping
struct ModeLock: Codable {
    let lockedMode: LocationMode
    let lockStartTime: Date
    let lockConfidence: Double

    static let unlockConfidenceRequirement: Double = 0.85
    static let minLockDuration: TimeInterval = 300   // 5 min to create lock
    static let maxLockDuration: TimeInterval = 600   // 10 min auto-expire

    /// Check if the lock should be released
    func shouldUnlock(newMode: LocationMode, newConfidence: Double, timestamp: Date) -> Bool {
        // Unlock if different mode with high confidence
        if newMode != lockedMode && newConfidence >= Self.unlockConfidenceRequirement {
            return true
        }
        // Unlock if expired
        return isExpired(timestamp: timestamp)
    }

    /// Check if the lock has expired
    func isExpired(timestamp: Date) -> Bool {
        return timestamp.timeIntervalSince(lockStartTime) > Self.maxLockDuration
    }

    /// Get remaining lock duration
    func remainingDuration(timestamp: Date) -> TimeInterval {
        let elapsed = timestamp.timeIntervalSince(lockStartTime)
        return max(0, Self.maxLockDuration - elapsed)
    }
}

// MARK: - Tunnel State

/// State tracking for tunnel detection
struct TunnelState: Codable {
    var isActive: Bool = false
    var startTime: Date?
    var preTunnelMode: LocationMode?

    static let maxDuration: TimeInterval = 600  // 10 min auto-expire

    init(isActive: Bool = false, startTime: Date? = nil, preTunnelMode: LocationMode? = nil) {
        self.isActive = isActive
        self.startTime = startTime
        self.preTunnelMode = preTunnelMode
    }

    mutating func enterTunnel(mode: LocationMode) {
        isActive = true
        startTime = Date()
        preTunnelMode = mode
    }

    mutating func exitTunnel() {
        isActive = false
        startTime = nil
        preTunnelMode = nil
    }

    func isExpired(timestamp: Date) -> Bool {
        guard let start = startTime else { return false }
        return timestamp.timeIntervalSince(start) > Self.maxDuration
    }
}

// MARK: - Detection Config

/// Configuration constants for detection algorithms
struct DetectionConfig {
    // Timing
    let minCheckIntervalMS: TimeInterval = 45
    let historyWindowMS: TimeInterval = 120

    // Sample requirements
    let minSamplesForTransition: Int = 3

    // Distance thresholds (meters)
    let zoneProbablyInside: Double = 10
    let zoneProbablyOutside: Double = 40

    // GPS accuracy thresholds
    let gpsAccuracyPenaltyThreshold: Double = 30
    let maxGPSAccuracyMeters: Double = 100

    // Speed thresholds (m/s)
    let stationarySpeedThresholdMS: Double = 0.8
    let motionThresholdMS: Double = 1.5

    // Confidence thresholds
    let confidenceThresholdForHistory: Double = 0.5

    // Vehicle detection
    let vehiclePersistenceWindow: TimeInterval = 300  // 5 minutes
    let vehicleDecayHalfLife: TimeInterval = 600      // 10 minutes
    let minVehicleConfidenceFloor: Double = 0.85

    // Cyclist exclusion
    let cyclistSpeedVarianceThreshold: Double = 1.5
    let cyclistMinSpeed: Double = 5.0

    static let `default` = DetectionConfig()
}

// MARK: - Motion State

/// Current motion analysis state
struct MotionState {
    let isStationary: Bool
    let isWalking: Bool
    let isRunning: Bool
    let isVehicle: Bool
    let justStartedMoving: Bool
    let activity: MotionActivity?
    let averageSpeed: Double
    let vehicleConfidence: Double

    static let unknown = MotionState(
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

// MARK: - Vehicle Analysis Result

/// Result of vehicle detection analysis
struct VehicleAnalysis {
    let isVehicle: Bool
    let confidence: Double
    let reason: String
    let isPersisted: Bool  // True if maintained through persistence

    static let notVehicle = VehicleAnalysis(
        isVehicle: false,
        confidence: 0,
        reason: "no_vehicle_evidence",
        isPersisted: false
    )
}

// MARK: - CLLocationCoordinate2D Codable Extension

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

// MARK: - Overpass Building

/// Building polygon data from OpenStreetMap via Overpass API
/// This is a type alias to avoid duplication - the actual struct is in OverpassService
typealias OverpassBuilding = OverpassService.OverpassBuilding

// MARK: - Array Extensions for Statistics

extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let avg = average
        let variance = map { pow($0 - avg, 2) }.reduce(0, +) / Double(count)
        return sqrt(variance)
    }
}
