import Foundation
import CoreLocation

// MARK: - UV Calculations
struct UVCalculations {

    // MARK: - SED Calculation
    /// Calculate Standard Erythemal Dose from UV Index and exposure time
    /// - Parameters:
    ///   - uvIndex: Current UV Index value
    ///   - exposureSeconds: Time exposed in seconds
    /// - Returns: SED value
    static func calculateSED(uvIndex: Double, exposureSeconds: Double) -> Double {
        // Formula: SED = UV_Index × 0.025 × exposure_seconds / 100
        return uvIndex * 0.025 * exposureSeconds / 100.0
    }

    // MARK: - MED Calculation
    /// Calculate personalized Minimal Erythemal Dose
    /// - Parameters:
    ///   - skinType: Fitzpatrick skin type (1-6)
    ///   - age: User's age
    ///   - gender: User's gender
    /// - Returns: MED value in J/m²
    static func calculateMED(skinType: Int, age: Int, gender: Gender) -> Int {
        // Base MED from skin type
        let baseMED: Int
        switch skinType {
        case 1: baseMED = 200   // Type I
        case 2: baseMED = 300   // Type II
        case 3: baseMED = 400   // Type III
        case 4: baseMED = 500   // Type IV
        case 5: baseMED = 750   // Type V
        case 6: baseMED = 1200  // Type VI
        default: baseMED = 400  // Default to Type III
        }

        // Age adjustment factor
        let ageAdjustment: Double
        if age < 18 {
            ageAdjustment = 0.9
        } else if age > 65 {
            ageAdjustment = 0.85
        } else {
            ageAdjustment = 1.0
        }

        // Gender adjustment factor
        let genderAdjustment: Double = (gender == .female) ? 1.1 : 1.0

        // Calculate final MED
        let adjustedMED = Double(baseMED) * ageAdjustment * genderAdjustment
        return Int(adjustedMED.rounded())
    }

    // MARK: - Exposure Ratio
    /// Calculate exposure ratio (session SED / user MED)
    /// - Parameters:
    ///   - sessionSED: Accumulated SED for current session
    ///   - userMED: User's personalized MED value
    /// - Returns: Exposure ratio (0.0 to n)
    static func calculateExposureRatio(sessionSED: Double, userMED: Int) -> Double {
        guard userMED > 0 else { return 0 }
        // Convert MED from J/m² to SED (1 SED = 100 J/m²)
        let medInSED = Double(userMED) / 100.0
        return sessionSED / medInSED
    }

    // MARK: - UV Index from Time
    /// Get background UV tracking interval based on UV index
    /// - Parameter uvIndex: Current UV Index
    /// - Returns: Update interval in seconds
    static func getTrackingInterval(for uvIndex: Double) -> TimeInterval {
        switch uvIndex {
        case ..<3:
            return 120  // 2 minutes for low UV
        case 3..<6:
            return 60   // 1 minute for moderate UV
        case 6..<8:
            return 30   // 30 seconds for high UV
        default:
            return 20   // 20 seconds for extreme UV
        }
    }

    // MARK: - Time to Burn
    /// Calculate approximate time to burn based on UV index and skin type
    /// - Parameters:
    ///   - uvIndex: Current UV Index
    ///   - userMED: User's MED value
    /// - Returns: Time in minutes until burning risk
    static func timeToBurn(uvIndex: Double, userMED: Int) -> Int? {
        guard uvIndex > 0 else { return nil }

        // Convert MED to SED
        let medInSED = Double(userMED) / 100.0

        // Calculate time in seconds to reach MED
        // Rearranging: SED = UV_Index × 0.025 × exposure_seconds / 100
        // exposure_seconds = SED × 100 / (UV_Index × 0.025)
        let secondsToBurn = (medInSED * 100.0) / (uvIndex * 0.025)

        // Convert to minutes
        return Int(secondsToBurn / 60.0)
    }

    // MARK: - Safe Exposure Time
    /// Calculate safe exposure time (75% of MED)
    /// - Parameters:
    ///   - uvIndex: Current UV Index
    ///   - userMED: User's MED value
    /// - Returns: Safe time in minutes
    static func safeExposureTime(uvIndex: Double, userMED: Int) -> Int? {
        guard let burnTime = timeToBurn(uvIndex: uvIndex, userMED: userMED) else {
            return nil
        }
        // Return 75% of burn time as safe exposure
        return Int(Double(burnTime) * 0.75)
    }
}

// MARK: - Vitamin D Calculations
struct VitaminDCalculations {

    // MARK: - Vitamin D Production
    /// Calculate Vitamin D production from sun exposure
    /// - Parameters:
    ///   - uvIndex: Current UV Index
    ///   - exposureSeconds: Time exposed in seconds
    ///   - bodyExposureFactor: Body exposure factor (0.1 to 0.8)
    ///   - skinType: Fitzpatrick skin type (1-6)
    ///   - latitude: Current latitude for solar angle calculation
    ///   - date: Current date/time
    /// - Returns: Vitamin D in IU
    static func calculateVitaminD(
        uvIndex: Double,
        exposureSeconds: Double,
        bodyExposureFactor: Double,
        skinType: Int,
        latitude: Double,
        date: Date
    ) -> Double {
        // Skip calculation if UV is too low
        guard uvIndex >= 3 else { return 0 }

        // Skin factor based on skin type
        let skinFactor: Double
        switch skinType {
        case 1, 2:
            skinFactor = 1.0  // Light skin - most efficient
        case 3, 4:
            skinFactor = 0.7  // Medium skin
        case 5, 6:
            skinFactor = 0.5  // Dark skin - less efficient
        default:
            skinFactor = 0.7
        }

        // Solar angle factor (simplified - peaks at solar noon)
        let solarAngleFactor = calculateSolarAngleFactor(latitude: latitude, date: date)

        // D-UV dose calculation
        let dUVDose = uvIndex * exposureSeconds / 60.0  // Convert seconds to minutes

        // Base Vitamin D production: 20 IU per unit D-UV dose
        let baseProduction = 20.0 * dUVDose

        // Apply all factors
        let vitaminD = baseProduction * bodyExposureFactor * skinFactor * solarAngleFactor

        // Cap at reasonable maximum per session (10,000 IU)
        return min(vitaminD, 10000)
    }

    // MARK: - Solar Angle Factor
    /// Calculate solar angle factor for Vitamin D production efficiency
    /// - Parameters:
    ///   - latitude: Current latitude
    ///   - date: Current date/time
    /// - Returns: Factor between 0 and 1
    private static func calculateSolarAngleFactor(latitude: Double, date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        // Convert to decimal hours
        let decimalHour = Double(hour) + Double(minute) / 60.0

        // Peak production around solar noon (simplified)
        // Assume solar noon is around 12:00 PM
        let solarNoon = 12.0

        // Calculate distance from solar noon
        let hoursFromNoon = abs(decimalHour - solarNoon)

        // Factor decreases as we move away from solar noon
        // Maximum at noon (1.0), minimum at sunrise/sunset (0.3)
        let factor: Double
        if hoursFromNoon <= 2 {
            factor = 1.0  // Peak hours (10 AM - 2 PM)
        } else if hoursFromNoon <= 4 {
            factor = 0.7  // Good hours (8-10 AM, 2-4 PM)
        } else if hoursFromNoon <= 6 {
            factor = 0.5  // Poor hours (6-8 AM, 4-6 PM)
        } else {
            factor = 0.3  // Very poor hours
        }

        // Adjust for latitude (higher latitudes = lower efficiency)
        let latitudeFactor = 1.0 - (abs(latitude) / 180.0) * 0.3

        return factor * latitudeFactor
    }

    // MARK: - Daily Target Progress
    /// Calculate progress towards daily Vitamin D target
    /// - Parameters:
    ///   - currentIU: Current accumulated IU
    ///   - targetIU: Daily target IU
    /// - Returns: Progress percentage (0.0 to 1.0)
    static func calculateProgress(currentIU: Double, targetIU: Double) -> Double {
        guard targetIU > 0 else { return 0 }
        return min(currentIU / targetIU, 1.0)
    }

    // MARK: - Remaining IU Needed
    /// Calculate remaining Vitamin D needed to reach target
    /// - Parameters:
    ///   - currentIU: Current accumulated IU
    ///   - targetIU: Daily target IU
    /// - Returns: Remaining IU needed
    static func remainingIU(currentIU: Double, targetIU: Double) -> Double {
        return max(targetIU - currentIU, 0)
    }

    // MARK: - Estimated Time to Target
    /// Estimate time needed to reach Vitamin D target
    /// - Parameters:
    ///   - remainingIU: IU still needed
    ///   - uvIndex: Current UV Index
    ///   - bodyExposureFactor: Current body exposure
    ///   - skinType: User's skin type
    ///   - latitude: Current latitude
    /// - Returns: Estimated minutes needed
    static func estimatedTimeToTarget(
        remainingIU: Double,
        uvIndex: Double,
        bodyExposureFactor: Double,
        skinType: Int,
        latitude: Double
    ) -> Int? {
        guard uvIndex >= 3, remainingIU > 0 else { return nil }

        // Calculate IU per minute based on current conditions
        let iuPerMinute = calculateVitaminD(
            uvIndex: uvIndex,
            exposureSeconds: 60,
            bodyExposureFactor: bodyExposureFactor,
            skinType: skinType,
            latitude: latitude,
            date: Date()
        )

        guard iuPerMinute > 0 else { return nil }

        // Calculate minutes needed
        let minutesNeeded = remainingIU / iuPerMinute
        return Int(ceil(minutesNeeded))
    }
}