import Foundation
import CoreLocation

/// Structured logging system for indoor/outdoor/vehicle detection debugging
/// Provides consistent, filterable logs with context and timing information
class DetectionLogger {

    // MARK: - Log Categories

    enum Category: String, CaseIterable {
        case detection = "DETECT"       // Core classification decisions
        case signal = "SIGNAL"          // Individual signal evaluations (GPS, floor, geofence, etc.)
        case motion = "MOTION"          // Motion/vehicle detection
        case transition = "TRANSIT"     // Mode changes and transitions
        case geofence = "GEOFNC"        // Geofence entry/exit events
        case performance = "PERF"       // Timing and performance metrics
        case state = "STATE"            // State management (locks, drift, tunnel)
        case uvTracking = "UVTRCK"      // UV tracking start/stop
        case error = "ERROR"            // Errors and warnings
        case debug = "DEBUG"            // Verbose debug information
    }

    enum Level: String {
        case debug = "🔍"
        case info = "ℹ️"
        case warning = "⚠️"
        case error = "❌"
        case success = "✅"
    }

    // MARK: - Configuration

    static var isVerboseMode = false
    static var enabledCategories: Set<Category> = Set(Category.allCases)

    // MARK: - Core Logging Methods

    /// Log a detection decision with full context
    static func logDetection(
        mode: LocationMode,
        confidence: Double,
        source: String,
        coordinate: CLLocationCoordinate2D,
        accuracy: Double?,
        motion: String,
        nearestBuilding: Double?,
        reasoning: String? = nil
    ) {
        guard shouldLog(.detection) else { return }

        var message = """

        ═══════════════════════════════════════════════════════════════
        🎯 DETECTION RESULT
        ═══════════════════════════════════════════════════════════════
        Mode:              \(mode.rawValue.uppercased())
        Confidence:        \(formatConfidence(confidence))
        Signal Source:     \(source)
        ───────────────────────────────────────────────────────────────
        Location:          \(formatCoordinate(coordinate))
        GPS Accuracy:      \(accuracy.map { formatAccuracy($0) } ?? "N/A")
        Motion:            \(motion)
        Nearest Building:  \(nearestBuilding.map { formatDistance($0) } ?? "N/A")
        """

        if let reasoning = reasoning {
            message += """

            ───────────────────────────────────────────────────────────────
            Reasoning:         \(reasoning)
            """
        }

        message += "\n═══════════════════════════════════════════════════════════════\n"

        print(message)
    }

    /// Log a signal evaluation (GPS pattern, floor, pressure, etc.)
    static func logSignal(
        type: String,
        result: String,
        confidence: Double?,
        details: [String: Any]? = nil
    ) {
        guard shouldLog(.signal) else { return }

        var message = "📡 [\(Category.signal.rawValue)] \(type): \(result)"

        if let confidence = confidence {
            message += " (confidence: \(formatConfidence(confidence)))"
        }

        if let details = details, !details.isEmpty {
            message += "\n   Details: \(formatDetails(details))"
        }

        print(message)
    }

    /// Log a mode transition with before/after context
    static func logTransition(
        from: LocationMode,
        to: LocationMode,
        confidence: Double,
        trigger: String,
        duration: TimeInterval? = nil
    ) {
        guard shouldLog(.transition) else { return }

        let durationStr = duration.map { " (was \(from.rawValue) for \(formatDuration($0)))" } ?? ""

        print("""
        🔄 [\(Category.transition.rawValue)] MODE CHANGE: \(from.rawValue) → \(to.rawValue)\(durationStr)
           Confidence: \(formatConfidence(confidence))
           Trigger:    \(trigger)
        """)
    }

    /// Log a geofence event
    static func logGeofence(
        event: String,
        buildingId: String,
        duration: TimeInterval? = nil,
        distance: Double? = nil
    ) {
        guard shouldLog(.geofence) else { return }

        var message = "📍 [\(Category.geofence.rawValue)] \(event): Building \(buildingId)"

        if let duration = duration {
            message += "\n   Duration in geofence: \(formatDuration(duration))"
        }

        if let distance = distance {
            message += "\n   Distance from building: \(formatDistance(distance))"
        }

        print(message)
    }

    /// Log motion analysis results
    static func logMotion(
        activity: String,
        speed: Double,
        vehicleConfidence: Double?,
        details: String? = nil
    ) {
        guard shouldLog(.motion) else { return }

        var message = "🚶 [\(Category.motion.rawValue)] Activity: \(activity), Speed: \(formatSpeed(speed))"

        if let vehicleConfidence = vehicleConfidence, vehicleConfidence > 0.7 {
            message += "\n   🚗 Vehicle confidence: \(formatConfidence(vehicleConfidence))"
        }

        if let details = details {
            message += "\n   \(details)"
        }

        print(message)
    }

    /// Log UV tracking events
    static func logUVTracking(
        action: String,
        mode: LocationMode,
        confidence: Double,
        uvIndex: Double? = nil,
        reason: String? = nil
    ) {
        guard shouldLog(.uvTracking) else { return }

        var message = "☀️ [\(Category.uvTracking.rawValue)] \(action.uppercased())"
        message += "\n   Mode:       \(mode.rawValue)"
        message += "\n   Confidence: \(formatConfidence(confidence))"

        if let uvIndex = uvIndex {
            message += "\n   UV Index:   \(String(format: "%.1f", uvIndex))"
        }

        if let reason = reason {
            message += "\n   Reason:     \(reason)"
        }

        print(message)
    }

    /// Log state management events (drift, lock, tunnel)
    static func logState(
        event: String,
        mode: LocationMode,
        details: [String: Any]
    ) {
        guard shouldLog(.state) else { return }

        print("""
        🔒 [\(Category.state.rawValue)] \(event.uppercased()): \(mode.rawValue)
           \(formatDetails(details))
        """)
    }

    /// Log performance metrics
    static func logPerformance(
        operation: String,
        duration: TimeInterval,
        success: Bool
    ) {
        guard shouldLog(.performance) else { return }

        let statusIcon = success ? "✅" : "❌"
        print("⏱️ [\(Category.performance.rawValue)] \(operation): \(formatDuration(duration)) \(statusIcon)")
    }

    /// Log general info with category
    static func log(
        _ message: String,
        category: Category = .debug,
        level: Level = .info
    ) {
        guard shouldLog(category) else { return }

        print("\(level.rawValue) [\(category.rawValue)] \(message)")
    }

    // MARK: - Helper Methods

    private static func shouldLog(_ category: Category) -> Bool {
        if category == .debug && !isVerboseMode {
            return false
        }
        return enabledCategories.contains(category)
    }

    private static func formatConfidence(_ confidence: Double) -> String {
        let percentage = Int(confidence * 100)
        let color = confidence >= 0.80 ? "🟢" : confidence >= 0.60 ? "🟡" : "🔴"
        return "\(color) \(percentage)%"
    }

    private static func formatAccuracy(_ accuracy: Double) -> String {
        let roundedAccuracy = Int(accuracy)
        let quality = accuracy < 20 ? "excellent" : accuracy < 40 ? "good" : accuracy < 80 ? "fair" : "poor"
        return "\(roundedAccuracy)m (\(quality))"
    }

    private static func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }

    private static func formatSpeed(_ speed: Double) -> String {
        let kmh = speed * 3.6
        return String(format: "%.1f km/h (%.1f m/s)", kmh, speed)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    private static func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private static func formatDetails(_ details: [String: Any]) -> String {
        details.map { key, value in
            "\(key): \(value)"
        }.joined(separator: "\n   ")
    }
}

// MARK: - Extensions

extension LocationMode {
    var emoji: String {
        switch self {
        case .inside: return "🏠"
        case .outside: return "🌳"
        case .vehicle: return "🚗"
        case .unknown: return "❓"
        }
    }
}
