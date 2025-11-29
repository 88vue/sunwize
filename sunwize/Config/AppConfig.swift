import Foundation

struct AppConfig {
    // MARK: - Supabase Configuration
    static let supabaseURL = URL(string: ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "https://mqrbyzjrsooryeuwdhrw.supabase.co")!
    static let supabaseKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1xcmJ5empyc29vcnlldXdkaHJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM0MjU4OTcsImV4cCI6MjA2OTAwMTg5N30.RgOafAuqMhtwIorxyNHLCWsIQnxe1qS_06OhugwtA8Y"

    // MARK: - API Configuration
    static let currentUVIndexBaseURL = "https://currentuvindex.com/api/v1"
    static let sunriseSunsetBaseURL = "https://api.sunrisesunset.io/json"
    static let overpassAPIURL = "https://overpass-api.de/api/interpreter"

    // MARK: - App Settings
    static let defaultDailyVitaminDTarget: Double = 600 // IU
    static let maxDailyVitaminDTarget: Double = 20000 // IU

    // MARK: - Background Task Intervals
    static let locationUpdateInterval: TimeInterval = 30 // seconds
    static let uvTrackingIntervalOutside: TimeInterval = 60 // seconds
    static let uvTrackingIntervalHigh: TimeInterval = 30 // seconds for UV > 6
    static let uvTrackingIntervalExtreme: TimeInterval = 20 // seconds for UV > 8

    // MARK: - Notification Settings
    static let uvWarningThreshold: Double = 0.75 // 75% of MED
    static let uvDangerThreshold: Double = 1.0 // 100% of MED
    static let notificationCooldown: TimeInterval = 300 // 5 minutes

    // MARK: - Cache Settings
    static let uvIndexCacheDuration: TimeInterval = 900 // 15 minutes
    static let sunTimesCacheDuration: TimeInterval = 86400 // 24 hours
    static let buildingDataCacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Location Settings
    static let locationAccuracyThreshold: Double = 40 // meters
    static let locationConfidenceThresholdHigh: Double = 0.70
    static let locationConfidenceThresholdLow: Double = 0.55
    static let significantLocationChangeDistance: Double = 25 // meters

    // MARK: - Sunscreen Settings
    static let sunscreenProtectionDuration: TimeInterval = 7200 // 2 hours
    
    // MARK: - Location Debounce Settings
    static let unknownHoldDebounce: TimeInterval = 90
}
