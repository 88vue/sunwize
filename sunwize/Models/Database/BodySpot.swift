import Foundation

// MARK: - Body Spot Model
struct BodySpot: Codable, Identifiable {
    let id: UUID
    let locationId: UUID
    let imageUrl: String
    let description: String?
    let bodyPart: String
    let asymmetry: Bool
    let border: BorderType
    let color: ColorType
    let diameter: Double
    let evolving: EvolvingType
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case locationId = "location_id"
        case imageUrl = "image_url"
        case description
        case bodyPart = "body_part"
        case asymmetry
        case border
        case color
        case diameter
        case evolving
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
