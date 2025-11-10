import Foundation

// MARK: - Vitamin D Data Model
struct VitaminDData: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: Date
    var totalIU: Double
    var targetIU: Double
    var bodyExposureFactor: Double
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case totalIU = "total_iu"
        case targetIU = "target_iu"
        case bodyExposureFactor = "body_exposure_factor"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Computed properties
    var progress: Double {
        guard targetIU > 0 else { return 0 }
        return min(totalIU / targetIU, 1.0)
    }

    var targetReached: Bool {
        return totalIU >= targetIU
    }
}

// MARK: - Body Exposure Levels
enum BodyExposureLevel: CaseIterable {
    case minimal      // Face and hands only (0.1)
    case light        // T-shirt and shorts (0.3)
    case moderate     // Tank top and shorts (0.5)
    case high         // Swimwear (0.8)

    var factor: Double {
        switch self {
        case .minimal: return 0.1
        case .light: return 0.3
        case .moderate: return 0.5
        case .high: return 0.8
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Face and hands only"
        case .light: return "T-shirt and shorts"
        case .moderate: return "Tank top and shorts"
        case .high: return "Swimwear"
        }
    }

    static func from(factor: Double) -> BodyExposureLevel {
        let closest = BodyExposureLevel.allCases.min { abs($0.factor - factor) < abs($1.factor - factor) }
        return closest ?? .light
    }
}
