import Foundation
import Combine
import CoreLocation

@MainActor
class UVTrackingViewModel: ObservableObject {
    // UV Tracking
    @Published var currentUVIndex: Double = 0.0
    @Published var sessionSED: Double = 0.0
    @Published var exposureRatio: Double = 0.0
    @Published var sessionStartTime: Date?
    @Published var uvSafeStreak: Int = 0
    @Published var uvForecast: [UVForecastData] = []
    @Published var uvHistory: [UVHistoryDay] = []
    
    // IMPROVEMENT: Sunscreen state now comes from BackgroundTaskManager (single source of truth)
    var sunscreenAppliedTime: Date? {
        BackgroundTaskManager.shared.sunscreenAppliedTime
    }
    
    // Computed property: sunscreen is active if applied within protection duration
    var sunscreenActive: Bool {
        BackgroundTaskManager.shared.isSunscreenProtectionActive
    }

    // Vitamin D Tracking
    @Published var currentVitaminD: Double = 0.0
    @Published var vitaminDTarget: Double = 600.0
    @Published var vitaminDProgress: Double = 0.0
    @Published var vitaminDStreak: Int = 0
    @Published var bodyExposureFactor: Double = 0.3
    @Published var vitaminDHistory: [VitaminDHistoryDay] = []

    // Settings
    @Published var isUVTrackingEnabled = true
    @Published var isVitaminDTrackingEnabled = true
    @Published var locationUncertaintyReason: LocationManager.LocationUncertaintyReason?
    
    // Daytime service
    private let daytimeService = DaytimeService.shared
    var isDaytime: Bool {
        daytimeService.isDaytime
    }
    
    // Sunrise/Sunset times (from daytime service)
    var sunriseTime: Date? {
        daytimeService.sunriseTime
    }
    var sunsetTime: Date? {
        daytimeService.sunsetTime
    }

    private var profile: Profile?
    private var vitaminDData: VitaminDData?
    private var updateTimer: Timer?
    private let supabase = SupabaseManager.shared
    private let backgroundTaskManager = BackgroundTaskManager.shared  // Single source for sessions
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupSubscriptions()
    }

    deinit {
        updateTimer?.invalidate()
    }

    // MARK: - Setup

    private func setupSubscriptions() {
        // Subscribe to location changes
        LocationManager.shared.$locationMode
            .sink { [weak self] mode in
                self?.handleLocationModeChange(mode)
            }
            .store(in: &cancellables)

        LocationManager.shared.$uncertaintyReason
            .sink { [weak self] reason in
                self?.locationUncertaintyReason = reason
            }
            .store(in: &cancellables)

        // Subscribe to UV index changes
        LocationManager.shared.$uvIndex
            .sink { [weak self] index in
                self?.currentUVIndex = index
            }
            .store(in: &cancellables)
        
        // IMPROVEMENT: Subscribe to location updates to fetch UV forecast when location becomes available
        LocationManager.shared.$currentLocation
            .compactMap { $0 } // Only emit when location is not nil
            .removeDuplicates { loc1, loc2 in
                // Avoid reloading for tiny location changes (within 100m)
                let distance = loc1.distance(from: loc2)
                return distance < 100
            }
            .sink { [weak self] location in
                guard let self = self else { return }
                
                print("📍 [UVTrackingViewModel] Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                
                // Always reload forecast when location changes significantly
                Task { @MainActor in
                    print("� [UVTrackingViewModel] Triggering UV forecast reload...")
                    await self.loadUVForecast()
                }
            }
            .store(in: &cancellables)
        
        // IMPROVEMENT: Subscribe to sunscreen state changes from BackgroundTaskManager
        // This ensures UI updates when sunscreen is applied via notification actions
        backgroundTaskManager.$sunscreenAppliedTime
            .sink { [weak self] _ in
                self?.objectWillChange.send()  // Trigger UI refresh
            }
            .store(in: &cancellables)
    }

    func startTracking(profile: Profile) {
        self.profile = profile
        loadUserData()
        startUpdateTimer()
        
        // Initialize sun times if needed (will skip if already updated today)
        Task {
            if daytimeService.shouldUpdateSunTimes(),
               let location = LocationManager.shared.currentLocation {
                await daytimeService.updateSunTimes(location: location)
            }
            
            // Start/stop location tracking based on daytime status
            if daytimeService.isDaytime {
                if !LocationManager.shared.isTracking {
                    LocationManager.shared.startLocationUpdates()
                    print("🌞 [UVTracking] Daytime - starting location tracking")
                }
            } else {
                // At night, make sure tracking is stopped
                if LocationManager.shared.isTracking {
                    LocationManager.shared.stopLocationUpdates()
                }
                print("🌙 [UVTracking] Nighttime - location tracking disabled for battery saving")
            }
        }
    }

    func stopTracking() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Stop location tracking when view disappears
        if LocationManager.shared.isTracking {
            LocationManager.shared.stopLocationUpdates()
            print("🛑 [UVTracking] Stopped location tracking")
        }
        
        // Session management now handled by BackgroundTaskManager
    }

    // MARK: - Location Mode Handling

    private func handleLocationModeChange(_ mode: LocationMode) {
        // IMPROVEMENT: BackgroundTaskManager now handles session lifecycle
        // ViewModel just observes and updates UI state
        Task {
            switch mode {
            case .outside:
                // Session managed by BackgroundTaskManager
                if sessionStartTime == nil {
                    sessionStartTime = Date()
                }
            case .inside, .vehicle, .unknown:
                // Session ended by BackgroundTaskManager
                sessionStartTime = nil
                sessionSED = 0.0
                exposureRatio = 0.0
            }
        }
    }

    // MARK: - UV Session Management (Removed - now handled by BackgroundTaskManager)
    // Sessions are managed centrally to avoid conflicts between foreground/background

    // MARK: - Update Timer

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                // Update sun times if needed (once per day)
                if self.daytimeService.shouldUpdateSunTimes(),
                   let location = LocationManager.shared.currentLocation {
                    await self.daytimeService.updateSunTimes(location: location)
                }
                
                // Only update tracking if it's daytime
                if self.daytimeService.isDaytime {
                    await self.updateTracking()
                }
                
                // Auto-stop location tracking if sunset occurred
                if !self.daytimeService.isDaytime && LocationManager.shared.isTracking {
                    LocationManager.shared.stopLocationUpdates()
                    print("🌇 [UVTracking] Sunset - stopping location tracking")
                }
            }
        }
    }

    private func updateTracking() async {
        guard let profile = profile else { return }

        // Update UV exposure
        if LocationManager.shared.locationMode == .outside && !sunscreenActive {
            let timeElapsed = Date().timeIntervalSince(sessionStartTime ?? Date())
            let sedIncrement = UVCalculations.calculateSED(
                uvIndex: currentUVIndex,
                exposureSeconds: min(timeElapsed, 60)
            )
            sessionSED += sedIncrement
            exposureRatio = UVCalculations.calculateExposureRatio(
                sessionSED: sessionSED,
                userMED: profile.med
            )

            // Update Vitamin D
            if isVitaminDTrackingEnabled {
                let vitaminDIncrement = VitaminDCalculations.calculateVitaminD(
                    uvIndex: currentUVIndex,
                    exposureSeconds: min(timeElapsed, 60),
                    bodyExposureFactor: bodyExposureFactor,
                    skinType: profile.skinType,
                    latitude: LocationManager.shared.currentLocation?.coordinate.latitude ?? 0,
                    date: Date()
                )
                currentVitaminD += vitaminDIncrement
                vitaminDProgress = currentVitaminD / vitaminDTarget
            }
        }
    }

    // MARK: - User Actions

    func applySunscreen() {
        // IMPROVEMENT: Delegate to BackgroundTaskManager (single source of truth)
        Task {
            await backgroundTaskManager.applySunscreen()
            // UI will update automatically via publisher subscription
        }
    }
    
    func clearExpiredSunscreen() {
        // Only clear if actually expired
        guard let appliedTime = sunscreenAppliedTime,
              Date().timeIntervalSince(appliedTime) >= AppConfig.sunscreenProtectionDuration else {
            return
        }
        backgroundTaskManager.sunscreenAppliedTime = nil
        print("🧴 [UVTrackingViewModel] Sunscreen protection expired and cleared")
    }

    func updateBodyExposure(_ factor: Double) {
        bodyExposureFactor = factor
        Task {
            await updateVitaminDData()
        }
    }

    func updateVitaminDTarget(_ target: Double) {
        vitaminDTarget = target
        vitaminDProgress = currentVitaminD / target
        Task {
            await updateVitaminDData()
        }
    }

    // MARK: - Data Loading

    private func loadUserData() {
        Task {
            guard let userId = profile?.id else { return }

            // Load streaks
            if let streaks = try? await supabase.getStreaks(userId: userId) {
                uvSafeStreak = streaks.uvSafeStreak
                vitaminDStreak = streaks.vitaminDStreak
            }

            // Load feature settings
            if let settings = try? await supabase.getFeatureSettings(userId: userId) {
                isUVTrackingEnabled = settings.uvTrackingEnabled
                isVitaminDTrackingEnabled = settings.vitaminDTrackingEnabled
            }

            // Load today's Vitamin D data
            if let vitaminD = try? await supabase.getVitaminDData(userId: userId, date: Date()) {
                vitaminDData = vitaminD
                currentVitaminD = vitaminD.totalIU
                vitaminDTarget = vitaminD.targetIU
                bodyExposureFactor = vitaminD.bodyExposureFactor
                vitaminDProgress = vitaminD.progress
            }

            // Load UV forecast
            await loadUVForecast()

            // Load history
            await loadHistory()
        }
    }

    private func loadUVForecast() async {
        guard let location = LocationManager.shared.currentLocation else {
            print("⚠️ [UVTrackingViewModel] Cannot load UV forecast: Location not available")
            return
        }

        print("📊 [UVTrackingViewModel] Loading UV forecast for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        do {
            let forecast = try await WeatherService.shared.getUVForecast(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            uvForecast = forecast
            print("✅ [UVTrackingViewModel] UV forecast loaded: \(forecast.count) data points")
            
            // Force UI update
            objectWillChange.send()
        } catch {
            print("❌ [UVTrackingViewModel] Error loading UV forecast: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
    }
    
    // Public method to retry loading forecast from UI
    func retryLoadForecast() async {
        await loadUVForecast()
    }

    private func loadHistory() async {
        guard let userId = profile?.id else { return }

        // Load last 7 days of UV history
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -6, to: endDate) ?? endDate

        do {
            let sessions = try await supabase.getUserSessions(userId: userId, date: Date())
            // Process sessions into history format
            // This is simplified - you'd group by day and calculate daily totals
            uvHistory = processUVHistory(sessions: sessions)
        } catch {
            print("Error loading UV history: \(error)")
        }
    }

    private func updateVitaminDData() async {
        guard var data = vitaminDData else { return }

        data.totalIU = currentVitaminD
        data.targetIU = vitaminDTarget
        data.bodyExposureFactor = bodyExposureFactor
        data.updatedAt = Date()

        do {
            try await supabase.updateVitaminDData(data)
        } catch {
            print("Error updating Vitamin D data: \(error)")
        }
    }

    // MARK: - Helpers

    private func processUVHistory(sessions: [UVSession]) -> [UVHistoryDay] {
        // Group sessions by day and create history entries
        // This is a simplified implementation
        var history: [UVHistoryDay] = []

        for day in 0..<7 {
            if let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) {
                let daySessions = sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                let totalSED = daySessions.reduce(0) { $0 + $1.sessionSED }
                let isSafe = totalSED < Double(profile?.med ?? 400) / 100.0

                history.append(UVHistoryDay(
                    date: date,
                    totalSED: totalSED,
                    isSafe: isSafe,
                    sessionCount: daySessions.count
                ))
            }
        }

        return history.reversed()
    }
}

// MARK: - Data Models
struct UVForecastData: Identifiable {
    let id = UUID()
    let time: Date
    let uvIndex: Double
}

struct UVHistoryDay: Identifiable {
    let id = UUID()
    let date: Date
    let totalSED: Double
    let isSafe: Bool
    let sessionCount: Int
}

struct VitaminDHistoryDay: Identifiable {
    let id = UUID()
    let date: Date
    let totalIU: Double
    let targetReached: Bool
}