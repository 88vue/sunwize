import SwiftUI

// MARK: - UV-Specific Colors
extension Color {
    // State Background Colors
    static let uvInsideBackground = Color(hex: "F3F4F6")!
    static let uvOutsideBackground = Color.white
    static let uvVehicleBackground = Color(hex: "EFF6FF")!
    static let uvUnknownBackground = Color(hex: "F9FAFB")!
    static let uvNightBackground = Color(hex: "1E293B")!
    static let uvSunSafeBackground = Color(hex: "ECFDF5")!

    // UV Index Level Colors
    static let uvLow = Color(hex: "22C55E")!      // Green
    static let uvModerate = Color(hex: "EAB308")!  // Yellow
    static let uvHigh = Color(hex: "F97316")!      // Orange (FF9500 from Figma)
    static let uvVeryHigh = Color(hex: "FF6B00")!  // Deep orange
    static let uvExtreme = Color(hex: "EF4444")!   // Red

    // Action Button Colors
    static let actionPrimary = Color(hex: "34C759")!  // Green for sunscreen
    static let actionSecondary = Color(hex: "E5E5EA")! // Gray for cover
    static let actionReapply = Color(hex: "FF9500")!  // Orange

    // UI Element Colors
    static let uvToggleBackground = Color(hex: "EBEBEB")!
    static let uvToggleSelected = Color.white
    static let uvStreakBackground = Color(hex: "FF9500")!

    // Progress Ring Colors
    static let progressRingBackground = Color(hex: "F3F4F6")!
    static let progressRingGreen = Color(hex: "34C759")!
    static let progressRingYellow = Color(hex: "FFCC00")!
    static let progressRingOrange = Color(hex: "FF9500")!
    static let progressRingRed = Color(hex: "FF3B30")!

    // Vitamin D Specific Colors
    static let vitaminDPrimary = Color(hex: "FFD700")!  // Gold
    static let vitaminDOrange = Color(hex: "FF9500")!   // Orange accent
    static let vitaminDBackground = Color(hex: "FFF9E6")! // Light yellow
    static let vitaminDText = Color(hex: "424242")!     // Dark gray for gold buttons
    static let vitaminDProgressGray = Color(hex: "F3F4F6")! // Light gray ring background
    static let vitaminDSliderBlue = Color(hex: "0075FF")! // Blue for body exposure slider
    static let vitaminDInfoBlue = Color(hex: "EFF6FF")! // Blue info box background
    static let vitaminDInfoBorder = Color(hex: "DBEAFE")! // Blue info box border
}

// MARK: - UV-Specific Spacing
extension Spacing {
    enum UV {
        static let islandPadding: CGFloat = 24
        static let islandSpacing: CGFloat = 16
        static let stateIconSize: CGFloat = 80
        static let progressRingSize: CGFloat = 200
        static let miniGraphHeight: CGFloat = 80
        static let togglePadding: CGFloat = 6
    }
}

// MARK: - UV-Specific Layout
extension Layout {
    enum UV {
        static let islandMinHeight: CGFloat = 120
        static let toggleHeight: CGFloat = 45
        static let toggleWidth: CGFloat = 326
        static let toggleButtonWidth: CGFloat = 155
        static let actionButtonHeight: CGFloat = 46
        static let bottomSheetMaxHeight: CGFloat = 600
        static let progressRingLineWidth: CGFloat = 12
        static let uvIndexIslandHeight: CGFloat = 64
        static let forecastIslandHeight: CGFloat = 148
        static let stateContainerHeight: CGFloat = 354
    }

    enum VitaminD {
        static let progressRingSize: CGFloat = 200
        static let progressRingLineWidth: CGFloat = 16
        static let dailyProgressIslandHeight: CGFloat = 76
        static let progressIslandHeight: CGFloat = 267
        static let bodyExposureIslandHeight: CGFloat = 180
        static let editTargetButtonHeight: CGFloat = 39
        static let editTargetButtonWidth: CGFloat = 234
        static let streakBadgeHeight: CGFloat = 37
        static let streakBadgeWidth: CGFloat = 115
        static let sliderThumbSize: CGFloat = 18
        static let sliderHeight: CGFloat = 8
    }
}

// MARK: - UV State Icons (SF Symbols)
enum UVStateIcon {
    static let inside = "house.fill"
    static let outside = "sun.max.fill"
    static let vehicle = "car.fill"
    static let unknown = "questionmark.circle.fill"
    static let nightTime = "moon.stars.fill"
    static let sunSafe = "checkmark.shield.fill"
    static let streak = "flame.fill"
    static let sunscreen = "sun.max"
    static let cover = "umbrella.fill"
    static let forecast = "chevron.right"
    static let checkmark = "checkmark"
    static let xmark = "xmark"
    static let close = "xmark"
}

// MARK: - Helper Functions
extension Color {
    /// Get UV index color based on level
    static func uvIndexColor(for uvIndex: Double) -> Color {
        switch uvIndex {
        case 0..<3:
            return .uvLow
        case 3..<6:
            return .uvModerate
        case 6..<8:
            return .uvHigh
        case 8..<11:
            return .uvVeryHigh
        default:
            return .uvExtreme
        }
    }

    /// Get UV index classification text
    static func uvIndexClassification(for uvIndex: Double) -> String {
        switch uvIndex {
        case 0..<3:
            return "Low"
        case 3..<6:
            return "Moderate"
        case 6..<8:
            return "High"
        case 8..<11:
            return "Very High"
        default:
            return "Extreme"
        }
    }

    /// Get progress ring color based on exposure ratio
    static func progressColor(for ratio: Double) -> Color {
        switch ratio {
        case 0..<0.5:
            return .progressRingGreen
        case 0.5..<0.75:
            return .progressRingYellow
        case 0.75..<0.9:
            return .progressRingOrange
        default:
            return .progressRingRed
        }
    }
}
