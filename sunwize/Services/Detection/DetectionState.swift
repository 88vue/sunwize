import Foundation
import CoreLocation

// MARK: - Detection State

/// The current state of location detection
/// This is the primary output of the DetectionEngine
struct DetectionState: Codable, Equatable {
    let mode: LocationMode
    let confidence: Double
    let source: SignalSource
    let reason: String?
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D?
    let accuracy: Double?
    let speed: Double?
    let activity: MotionActivity?

    // Additional context for UV tracking decisions
    let polygonOccupancyDuration: TimeInterval?
    let isStationaryNearBuilding: Bool
    let stationaryDuration: TimeInterval?
    let nearestBuildingDistance: Double?

    // MARK: - Computed Properties

    /// True if confidence is high enough for reliable classification
    var isHighConfidence: Bool { confidence >= 0.85 }

    /// True if state is suitable for starting UV tracking
    var isStableForUVTracking: Bool { confidence >= 0.85 && mode == .outside }

    /// Latitude accessor
    var latitude: Double { coordinate?.latitude ?? 0 }

    /// Longitude accessor
    var longitude: Double { coordinate?.longitude ?? 0 }

    // MARK: - Equatable

    static func == (lhs: DetectionState, rhs: DetectionState) -> Bool {
        lhs.mode == rhs.mode &&
        lhs.confidence == rhs.confidence &&
        lhs.source == rhs.source &&
        lhs.timestamp == rhs.timestamp
    }

    // MARK: - Initializers

    init(
        mode: LocationMode,
        confidence: Double,
        source: SignalSource,
        reason: String? = nil,
        timestamp: Date = Date(),
        coordinate: CLLocationCoordinate2D? = nil,
        accuracy: Double? = nil,
        speed: Double? = nil,
        activity: MotionActivity? = nil,
        polygonOccupancyDuration: TimeInterval? = nil,
        isStationaryNearBuilding: Bool = false,
        stationaryDuration: TimeInterval? = nil,
        nearestBuildingDistance: Double? = nil
    ) {
        self.mode = mode
        self.confidence = confidence
        self.source = source
        self.reason = reason
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.accuracy = accuracy
        self.speed = speed
        self.activity = activity
        self.polygonOccupancyDuration = polygonOccupancyDuration
        self.isStationaryNearBuilding = isStationaryNearBuilding
        self.stationaryDuration = stationaryDuration
        self.nearestBuildingDistance = nearestBuildingDistance
    }

    /// Create an unknown state
    static func unknown(
        coordinate: CLLocationCoordinate2D? = nil,
        accuracy: Double? = nil,
        reason: String? = nil
    ) -> DetectionState {
        DetectionState(
            mode: .unknown,
            confidence: 0.5,
            source: .fallback,
            reason: reason ?? "insufficient_evidence",
            coordinate: coordinate,
            accuracy: accuracy
        )
    }

    /// Create state from a classification result
    static func from(
        result: ClassificationResult,
        coordinate: CLLocationCoordinate2D?,
        accuracy: Double?,
        speed: Double?,
        activity: MotionActivity?,
        polygonOccupancyDuration: TimeInterval? = nil,
        isStationaryNearBuilding: Bool = false,
        stationaryDuration: TimeInterval? = nil,
        nearestBuildingDistance: Double? = nil
    ) -> DetectionState {
        DetectionState(
            mode: result.mode,
            confidence: result.confidence,
            source: result.signalSource,
            reason: result.reason,
            coordinate: coordinate,
            accuracy: accuracy,
            speed: speed,
            activity: activity,
            polygonOccupancyDuration: polygonOccupancyDuration,
            isStationaryNearBuilding: isStationaryNearBuilding,
            stationaryDuration: stationaryDuration,
            nearestBuildingDistance: nearestBuildingDistance
        )
    }
}

// MARK: - Location State (Legacy Compatibility)

/// Legacy LocationState struct for backward compatibility with BackgroundTaskManager
/// Maps to the old LocationManager.LocationState interface
extension DetectionState {
    /// Convert to the legacy LocationState format
    var asLegacyState: LegacyLocationState {
        LegacyLocationState(
            mode: mode,
            confidence: confidence,
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            speed: speed,
            activity: activity,
            uncertaintyReason: nil
        )
    }
}

/// Legacy location state format for backward compatibility
struct LegacyLocationState {
    let mode: LocationMode
    let confidence: Double
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let speed: Double?
    let activity: MotionActivity?
    let uncertaintyReason: LocationUncertaintyReason?

    var timestamp: Date { Date() }
}

// MARK: - Detection Context

/// Additional context gathered during detection
/// Used internally by DetectionEngine
struct DetectionContext {
    let location: CLLocation
    let buildings: [OverpassBuilding]?
    let insidePolygon: OverpassBuilding?
    let nearestDistance: Double?
    let vehicleAnalysis: VehicleAnalysis
    let accuracyStats: AccuracyStats
    let motion: MotionState
    let stationaryDuration: TimeInterval
    let isInStartupPhase: Bool

    /// True if currently inside any building polygon
    var isInsideAnyPolygon: Bool { insidePolygon != nil }

    /// True if near a building (within zone threshold)
    var isNearBuilding: Bool {
        guard let distance = nearestDistance else { return false }
        return distance < DetectionConfig.default.zoneProbablyOutside
    }

    /// True if very close to a building
    var isVeryCloseToBuilding: Bool {
        guard let distance = nearestDistance else { return false }
        return distance < DetectionConfig.default.zoneProbablyInside
    }
}
