import Foundation

// MARK: - ABCDE Assessment Types
enum BorderType: String, Codable, CaseIterable {
    case regular = "Regular"
    case irregular = "Irregular"
    case ragged = "Ragged"
}

enum ColorType: String, Codable, CaseIterable {
    case uniform = "Uniform"
    case varied = "Varied"
    case multiple = "Multiple"
}

enum EvolvingType: String, Codable, CaseIterable {
    case unchanged = "Unchanged"
    case growing = "Growing"
    case changing = "Changing"
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
