import Foundation
import CoreLocation
import Combine

/// Centralized service for determining if it's daytime based on actual sunrise/sunset times
/// Thread-safe - can be accessed from main actor or background contexts
class DaytimeService: ObservableObject {
    static let shared = DaytimeService()
    
    @Published private(set) var isDaytime: Bool = true
    @Published private(set) var sunriseTime: Date?
    @Published private(set) var sunsetTime: Date?
    
    private var lastSunTimesUpdate: Date?
    private var checkTimer: Timer?
    private let queue = DispatchQueue(label: "com.sunwize.daytimeservice", qos: .userInitiated)
    
    private init() {
        // Initial check with fallback
        checkDaytimeStatus()
        
        // Check every 5 minutes
        DispatchQueue.main.async { [weak self] in
            self?.startCheckTimer()
        }
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    // MARK: - Public API
    
    /// Update sun times for a specific location
    func updateSunTimes(location: CLLocation) async {
        do {
            let sunTimes = try await WeatherService.shared.getSunTimes(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                date: Date()
            )
            
            if let sunTimes = sunTimes {
                if let sunrise = sunTimes.sunriseDate,
                   let sunset = sunTimes.sunsetDate {
                    
                    // Update on main thread since these are @Published
                    await MainActor.run {
                        self.sunriseTime = sunrise
                        self.sunsetTime = sunset
                        self.lastSunTimesUpdate = Date()
                    }
                    
                    print("☀️ [DaytimeService] Sun times updated: Sunrise \(sunrise.formatted(date: .omitted, time: .shortened)), Sunset \(sunset.formatted(date: .omitted, time: .shortened))")
                    
                    // Immediately check daytime status with new times
                    checkDaytimeStatus()
                } else {
                    print("❌ [DaytimeService] Failed to parse sunrise/sunset dates")
                }
            }
        } catch {
            print("❌ [DaytimeService] Error fetching sun times: \(error.localizedDescription)")
        }
    }
    
    /// Force a daytime status check (useful after location changes)
    func checkNow() {
        checkDaytimeStatus()
    }
    
    // MARK: - Private Methods
    
    private func startCheckTimer() {
        // Timer must run on main thread
        // Check every 5 minutes to catch sunrise/sunset
        checkTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkDaytimeStatus()
        }
    }
    
    private func checkDaytimeStatus() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let wasDay = self.isDaytime
            
            if let sunrise = self.sunriseTime, let sunset = self.sunsetTime {
                // Use actual sunrise/sunset times
                let newIsDaytime = now >= sunrise && now <= sunset
                
                if self.isDaytime != newIsDaytime {
                    DispatchQueue.main.async {
                        self.isDaytime = newIsDaytime
                    }
                }
            } else {
                // Fallback to simple hour check if sun times not available
                let hour = Calendar.current.component(.hour, from: now)
                let newIsDaytime = hour >= 6 && hour <= 20
                
                if self.isDaytime != newIsDaytime {
                    DispatchQueue.main.async {
                        self.isDaytime = newIsDaytime
                    }
                }
                
                print("⚠️ [DaytimeService] Using fallback daytime check (6 AM - 8 PM)")
            }
            
            // Log transitions only
            if self.isDaytime != wasDay {
                if self.isDaytime {
                    print("🌅 [DaytimeService] Sunrise detected - daytime mode activated")
                } else {
                    print("🌇 [DaytimeService] Sunset detected - nighttime mode activated")
                }
            }
        }
    }
    
    /// Check if sun times need updating (once per day)
    func shouldUpdateSunTimes() -> Bool {
        return lastSunTimesUpdate == nil ||
            !Calendar.current.isDateInToday(lastSunTimesUpdate ?? Date.distantPast)
    }
}
