import Foundation

// MARK: - Profile Model
struct Profile: Codable, Identifiable {
    let id: UUID
    let email: String
    var name: String
    var age: Int
    var gender: Gender
    var skinType: Int
    var med: Int // Minimal Erythemal Dose in J/m²
    var onboardingCompleted: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, name, age, gender
        case skinType = "skin_type"
        case med
        case onboardingCompleted = "onboarding_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Gender Enum
enum Gender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case nonBinary = "Non-binary"
    case preferNotToSay = "Prefer not to say"

    var displayName: String {
        self.rawValue
    }
}

// MARK: - Fitzpatrick Skin Type
enum FitzpatrickSkinType: Int, CaseIterable {
    case typeI = 1
    case typeII = 2
    case typeIII = 3
    case typeIV = 4
    case typeV = 5
    case typeVI = 6

    var description: String {
        switch self {
        case .typeI:
            return "Always burns, never tans"
        case .typeII:
            return "Burns easily, tans minimally"
        case .typeIII:
            return "Burns moderately, tans gradually"
        case .typeIV:
            return "Burns minimally, tans easily"
        case .typeV:
            return "Rarely burns, tans easily"
        case .typeVI:
            return "Never burns, always tans"
        }
    }

    var baseMED: Int {
        switch self {
        case .typeI: return 200
        case .typeII: return 300
        case .typeIII: return 400
        case .typeIV: return 500
        case .typeV: return 750
        case .typeVI: return 1200
        }
    }

    var sedValue: Double {
        return Double(baseMED) / 100.0
    }
}