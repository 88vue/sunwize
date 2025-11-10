import Foundation

// MARK: - Streaks Model
struct Streaks: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var uvSafeStreak: Int
    var vitaminDStreak: Int
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case uvSafeStreak = "uv_safe_streak"
        case vitaminDStreak = "vitamin_d_streak"
        case lastUpdated = "last_updated"
    }
}

// MARK: - Feature Settings Model
struct FeatureSettings: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var uvTrackingEnabled: Bool
    var vitaminDTrackingEnabled: Bool
    var bodyScanRemindersEnabled: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case uvTrackingEnabled = "uv_tracking_enabled"
        case vitaminDTrackingEnabled = "vitamin_d_tracking_enabled"
        case bodyScanRemindersEnabled = "body_scan_reminders_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}