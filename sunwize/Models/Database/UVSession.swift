import Foundation

// MARK: - UV Session Model
struct UVSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: Date
    let startTime: Date
    var endTime: Date?
    var sessionSED: Double
    var sunscreenApplied: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case sessionSED = "session_sed"
        case sunscreenApplied = "sunscreen_applied"
        case createdAt = "created_at"
    }

    // Computed properties
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    var isActive: Bool {
        return endTime == nil
    }
}

// MARK: - UV Exposure Risk Levels
enum UVExposureRisk {
    case veryLow    // < 0.25
    case low        // 0.25-0.5
    case moderate   // 0.5-0.75
    case high       // 0.75-1.0
    case veryHigh   // 1.0-1.5
    case extreme    // > 1.5

    static func from(exposureRatio: Double) -> UVExposureRisk {
        switch exposureRatio {
        case ..<0.25:
            return .veryLow
        case 0.25..<0.5:
            return .low
        case 0.5..<0.75:
            return .moderate
        case 0.75..<1.0:
            return .high
        case 1.0..<1.5:
            return .veryHigh
        default:
            return .extreme
        }
    }

    var color: String {
        switch self {
        case .veryLow:
            return "#00C851"  // Green
        case .low:
            return "#33B5E5"  // Light Blue
        case .moderate:
            return "#FFBB33"  // Orange
        case .high:
            return "#FF8800"  // Dark Orange
        case .veryHigh:
            return "#FF4444"  // Red
        case .extreme:
            return "#CC0000"  // Dark Red
        }
    }

    var description: String {
        switch self {
        case .veryLow:
            return "Very Low - Well below erythemal threshold"
        case .low:
            return "Low - Below erythemal threshold"
        case .moderate:
            return "Moderate - Approaching erythemal threshold"
        case .high:
            return "High - Near erythemal threshold (warning zone)"
        case .veryHigh:
            return "Very High - Above threshold, mild erythema likely"
        case .extreme:
            return "Extreme - Significant erythema risk"
        }
    }
}
