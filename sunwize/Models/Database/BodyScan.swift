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

// MARK: - ABCDE Assessment Types
enum BorderType: String, Codable, CaseIterable {
    case regular = "Regular"
    case irregular = "Irregular"
}

enum ColorType: String, Codable, CaseIterable {
    case uniform = "Uniform"
    case varied = "Varied"
}

enum EvolvingType: String, Codable, CaseIterable {
    case shrunk = "Shrunk"
    case unchanged = "Unchanged"
    case grown = "Grown"
}

// MARK: - Body Part Enum
enum BodyPart: String, CaseIterable {
    case head = "Head"
    case neck = "Neck"
    case chest = "Chest"
    case abdomen = "Abdomen"
    case back = "Back"
    case leftArm = "Left Arm"
    case rightArm = "Right Arm"
    case leftLeg = "Left Leg"
    case rightLeg = "Right Leg"
    case leftHand = "Left Hand"
    case rightHand = "Right Hand"
    case leftFoot = "Left Foot"
    case rightFoot = "Right Foot"

    static func from(coordinates: SIMD3<Float>) -> BodyPart {
        // Determine body part based on 3D coordinates
        // This is a simplified mapping - adjust based on your 3D model
        let y = coordinates.y
        let x = coordinates.x

        if y > 1.5 {
            return .head
        } else if y > 1.3 {
            return .neck
        } else if y > 0.8 {
            if abs(x) > 0.4 {
                return x > 0 ? .rightArm : .leftArm
            }
            return coordinates.z > 0 ? .chest : .back
        } else if y > 0.2 {
            return .abdomen
        } else if y > -0.5 {
            return x > 0 ? .rightLeg : .leftLeg
        } else {
            return x > 0 ? .rightFoot : .leftFoot
        }
    }
}