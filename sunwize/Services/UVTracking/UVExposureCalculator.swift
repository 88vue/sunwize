import Foundation

// MARK: - UV Exposure Calculator

/// Calculator for UV exposure metrics (SED, MED ratio)
/// Wraps existing UVCalculations utility
class UVExposureCalculator {

    // MARK: - SED Calculations

    /// Calculate Standard Erythema Dose from UV exposure
    /// - Parameters:
    ///   - uvIndex: Current UV index
    ///   - exposureSeconds: Duration of exposure in seconds
    /// - Returns: SED value
    static func calculateSED(uvIndex: Double, exposureSeconds: TimeInterval) -> Double {
        return UVCalculations.calculateSED(uvIndex: uvIndex, exposureSeconds: exposureSeconds)
    }

    /// Calculate exposure ratio relative to user's MED
    /// - Parameters:
    ///   - sessionSED: Total session SED
    ///   - userMED: User's Minimal Erythema Dose
    /// - Returns: Exposure ratio (0.0 - 1.0+)
    static func calculateExposureRatio(sessionSED: Double, userMED: Double) -> Double {
        return UVCalculations.calculateExposureRatio(sessionSED: sessionSED, userMED: Int(userMED))
    }

    // MARK: - Tracking Interval

    /// Get recommended tracking interval based on UV index
    /// Higher UV = more frequent updates
    /// - Parameter uvIndex: Current UV index
    /// - Returns: Interval in seconds
    static func getTrackingInterval(for uvIndex: Double) -> TimeInterval {
        return UVCalculations.getTrackingInterval(for: uvIndex)
    }

    // MARK: - Threshold Checks

    /// Check if exposure is approaching warning level (80% of MED)
    static func isApproachingWarning(exposureRatio: Double) -> Bool {
        return exposureRatio >= 0.70 && exposureRatio < 0.80
    }

    /// Check if exposure is at warning level (80% of MED)
    static func isAtWarning(exposureRatio: Double) -> Bool {
        return exposureRatio >= 0.80 && exposureRatio < 1.0
    }

    /// Check if exposure has reached danger level (100% of MED)
    static func isAtDanger(exposureRatio: Double) -> Bool {
        return exposureRatio >= 1.0
    }

    /// Get exposure status category
    static func getExposureStatus(exposureRatio: Double) -> ExposureStatus {
        if exposureRatio >= 1.0 {
            return .danger
        } else if exposureRatio >= 0.80 {
            return .warning
        } else if exposureRatio >= 0.50 {
            return .moderate
        } else {
            return .safe
        }
    }

    enum ExposureStatus {
        case safe
        case moderate
        case warning
        case danger

        var description: String {
            switch self {
            case .safe: return "Safe"
            case .moderate: return "Moderate"
            case .warning: return "Approaching limit"
            case .danger: return "Limit exceeded"
            }
        }
    }

    // MARK: - Sunscreen Adjustment

    /// Adjust UV exposure for sunscreen protection
    /// SPF 30 blocks ~97% of UV, SPF 50 blocks ~98%
    static func adjustForSunscreen(uvIndex: Double, spf: Int) -> Double {
        guard spf > 1 else { return uvIndex }

        let protectionFactor = 1.0 / Double(spf)
        return uvIndex * protectionFactor
    }

    /// Calculate time until warning threshold
    /// - Parameters:
    ///   - currentSED: Current accumulated SED
    ///   - userMED: User's MED threshold
    ///   - uvIndex: Current UV index
    /// - Returns: Time in seconds until 80% MED, or nil if already past
    static func timeUntilWarning(
        currentSED: Double,
        userMED: Double,
        uvIndex: Double
    ) -> TimeInterval? {
        let warningSED = userMED * 0.80
        let remainingSED = warningSED - currentSED

        guard remainingSED > 0, uvIndex > 0 else { return nil }

        // Reverse calculate: SED = UV * time / 100, so time = SED * 100 / UV
        return (remainingSED * 100.0) / uvIndex
    }

    /// Calculate time until danger threshold
    static func timeUntilDanger(
        currentSED: Double,
        userMED: Double,
        uvIndex: Double
    ) -> TimeInterval? {
        let dangerSED = userMED
        let remainingSED = dangerSED - currentSED

        guard remainingSED > 0, uvIndex > 0 else { return nil }

        return (remainingSED * 100.0) / uvIndex
    }
}
