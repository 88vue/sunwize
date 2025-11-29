import Foundation

// MARK: - Body Location Model
struct BodyLocation: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let coordX: Double
    let coordY: Double
    let coordZ: Double
    let bodyPart: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case coordX = "coord_x"
        case coordY = "coord_y"
        case coordZ = "coord_z"
        case bodyPart = "body_part"
        case createdAt = "created_at"
    }

    var coordinates: SIMD3<Float> {
        return SIMD3<Float>(Float(coordX), Float(coordY), Float(coordZ))
    }
}
