import Foundation

// MARK: - UV Index Response
struct UVIndexResponse: Codable {
    let lat: Double
    let lon: Double
    let data: [UVIndexData]
}

struct UVIndexData: Codable {
    let dateTime: String
    let uvIndex: Double
    let uvIndexMax: Double?

    enum CodingKeys: String, CodingKey {
        case dateTime = "date_time"
        case uvIndex = "uv_index"
        case uvIndexMax = "uv_index_max"
    }
}

// MARK: - Sun Times Response
struct SunTimesResponse: Codable {
    let results: SunTimes
    let status: String
}

struct SunTimes: Codable {
    let sunrise: String
    let sunset: String
    let solarNoon: String
    let dayLength: String
    let civilTwilightBegin: String?
    let civilTwilightEnd: String?

    enum CodingKeys: String, CodingKey {
        case sunrise
        case sunset
        case solarNoon = "solar_noon"
        case dayLength = "day_length"
        case civilTwilightBegin = "civil_twilight_begin"
        case civilTwilightEnd = "civil_twilight_end"
    }

    var sunriseDate: Date? {
        // The API returns times like "5:47:16 AM" or "7:43:22 PM"
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let time = formatter.date(from: sunrise) else {
            print("⚠️ [SunTimes] Failed to parse sunrise: '\(sunrise)'")
            return nil
        }
        
        // Combine with today's date
        let calendar = Calendar.current
        let now = Date()
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second
        
        return calendar.date(from: combined)
    }

    var sunsetDate: Date? {
        // The API returns times like "5:47:16 AM" or "7:43:22 PM"
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let time = formatter.date(from: sunset) else {
            print("⚠️ [SunTimes] Failed to parse sunset: '\(sunset)'")
            return nil
        }
        
        // Combine with today's date
        let calendar = Calendar.current
        let now = Date()
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second
        
        return calendar.date(from: combined)
    }
}

// MARK: - Location Mode
enum LocationMode: String, Codable {
    case inside = "inside"
    case outside = "outside"
    case vehicle = "vehicle"
    case unknown = "unknown"
}

// MARK: - UV Index Level
enum UVIndexLevel: CaseIterable {
    case low        // 0-2
    case moderate   // 3-5
    case high       // 6-7
    case veryHigh   // 8-10
    case extreme    // 11+

    static func from(uvIndex: Double) -> UVIndexLevel {
        switch uvIndex {
        case 0..<3:
            return .low
        case 3..<6:
            return .moderate
        case 6..<8:
            return .high
        case 8..<11:
            return .veryHigh
        default:
            return .extreme
        }
    }

    var description: String {
        switch self {
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        case .veryHigh:
            return "Very High"
        case .extreme:
            return "Extreme"
        }
    }

    var color: String {
        switch self {
        case .low:
            return "#00C851"
        case .moderate:
            return "#FFBB33"
        case .high:
            return "#FF8800"
        case .veryHigh:
            return "#FF4444"
        case .extreme:
            return "#CC0000"
        }
    }

    var recommendedAction: String {
        switch self {
        case .low:
            return "Minimal sun protection required"
        case .moderate:
            return "Sun protection required if outside for more than 1 hour"
        case .high:
            return "Sun protection required. Seek shade during midday hours"
        case .veryHigh:
            return "Extra sun protection required. Avoid being outside during midday hours"
        case .extreme:
            return "Maximum sun protection required. Avoid being outside if possible"
        }
    }
}