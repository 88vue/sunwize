import Foundation
import Combine
import CoreLocation

@MainActor
class UVTrackingViewModel: ObservableObject {
    // UV Tracking
    @Published var currentUVIndex: Double = 0.0
    /// Display UV index - always up to date regardless of indoor/outdoor status
    /// Use this for UI display (UVIndexIsland). Updated every 15 minutes during daytime.
    @Published var displayUVIndex: Double = 0.0
    @Published var sessionSED: Double = 0.0
    @Published var exposureRatio: Double = 0.0
    @Published var sessionStartTime: Date?
    @Published var uvSafeStreak: Int = 0
    @Published var uvForecast: [UVForecastData] = []
    @Published var uvHistory: [UVHistoryDay] = []

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

    // Sunscreen Tracking
    @Published var sunscreenActive = false {
        didSet {
            // Persist to UserDefaults for background access
            UserDefaults.standard.set(sunscreenActive, forKey: "sunscreenActive")
            if sunscreenActive {
                UserDefaults.standard.set(sunscreenAppliedTime?.timeIntervalSince1970, forKey: "sunscreenAppliedTime")
            } else {
                UserDefaults.standard.removeObject(forKey: "sunscreenAppliedTime")
            }
        }
    }
    @Published var sunscreenAppliedTime: Date?

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
    private var uvRefreshTimer: Timer?  // Timer for keeping displayUVIndex up to date
    private var lastUVRefreshTime: Date?
    private let supabase = SupabaseManager.shared
    private let backgroundTaskManager = BackgroundTaskManager.shared  // Single source for sessions
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Restore sunscreen state from UserDefaults
        restoreSunscreenState()
        setupSubscriptions()
    }

    deinit {
        updateTimer?.invalidate()
        uvRefreshTimer?.invalidate()
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

        BackgroundTaskManager.shared.$isUVTrackingActive
            .sink { [weak self] active in
                guard let self = self else { return }
                if !active {
                    // Session ended - clear UI state
                    self.sessionStartTime = nil
                    self.sessionSED = 0.0
                    self.exposureRatio = 0.0
                }
            }
            .store(in: &cancellables)

        // Subscribe to backend session state (single source of truth)
        BackgroundTaskManager.shared.$currentSessionSED
            .sink { [weak self] sed in
                self?.sessionSED = sed
            }
            .store(in: &cancellables)

        BackgroundTaskManager.shared.$currentSessionStartTime
            .sink { [weak self] startTime in
                self?.sessionStartTime = startTime
            }
            .store(in: &cancellables)

        BackgroundTaskManager.shared.$currentExposureRatio
            .sink { [weak self] ratio in
                self?.exposureRatio = ratio
            }
            .store(in: &cancellables)

        // Subscribe to Vitamin D tracking state (single source of truth)
        BackgroundTaskManager.shared.$currentVitaminD
            .sink { [weak self] vitaminD in
                self?.currentVitaminD = vitaminD
            }
            .store(in: &cancellables)

        BackgroundTaskManager.shared.$vitaminDProgress
            .sink { [weak self] progress in
                self?.vitaminDProgress = progress
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
            .dropFirst() // Skip initial value to avoid duplicate load on startup
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main) // Debounce rapid updates
            .sink { [weak self] location in
                guard let self = self else { return }

                print("📍 [UVTrackingViewModel] Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")

                // Always reload forecast when location changes significantly
                Task { @MainActor in
                    print("🔄 [UVTrackingViewModel] Triggering UV forecast reload...")
                    await self.loadUVForecast()
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to UV session end notifications to reload history
        NotificationCenter.default.publisher(for: NSNotification.Name("UVSessionEnded"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    print("📊 [UVTrackingViewModel] UV session ended - reloading history")
                    await self?.loadHistory()
                }
            }
            .store(in: &cancellables)

        // Subscribe to day change notifications (midnight reset)
        NotificationCenter.default.publisher(for: NSNotification.Name("DayChanged"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    print("🌅 [UVTrackingViewModel] Day changed - resetting and reloading")
                    self?.currentVitaminD = 0.0
                    self?.vitaminDProgress = 0.0
                    self?.sessionSED = 0.0
                    self?.exposureRatio = 0.0
                    await self?.loadHistory()
                }
            }
            .store(in: &cancellables)
    }

    func startTracking(profile: Profile) {
        self.profile = profile
        loadUserData()
        startUpdateTimer()
        startUVRefreshTimer()  // Start periodic UV refresh for display

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
        uvRefreshTimer?.invalidate()
        uvRefreshTimer = nil

        // Stop location tracking when view disappears
        if LocationManager.shared.isTracking {
            LocationManager.shared.stopLocationUpdates()
            print("🛑 [UVTracking] Stopped location tracking")
        }

        // Session management now handled by BackgroundTaskManager
    }

    // MARK: - Location Mode Handling

    private func handleLocationModeChange(_ mode: LocationMode) {
        // BackgroundTaskManager handles all session lifecycle
        // ViewModel subscribes to published session state - no action needed here
        // This method kept for potential future UI-specific location mode handling
    }

    // MARK: - UV Session Management (Removed - now handled by BackgroundTaskManager)
    // Sessions are managed centrally to avoid conflicts between foreground/background
    // UI state synchronized via Combine subscriptions to BackgroundTaskManager published properties

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
        // UV exposure tracking now handled entirely by BackgroundTaskManager
        // UI automatically updates via Combine subscriptions to published properties
        // This timer now only handles:
        // 1. Sun times updates (once per day)
        // 2. Stopping location tracking at sunset

        // Note: Vitamin D tracking is also handled by BackgroundTaskManager
        // Frontend only displays the data, doesn't calculate it
    }

    // MARK: - UV Display Refresh Timer

    /// Starts a timer that refreshes displayUVIndex every 15 minutes during daytime
    /// This ensures the UV Index Island always shows current data, even when indoors
    private func startUVRefreshTimer() {
        // Refresh every 15 minutes (matches cache duration)
        uvRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Only refresh during daytime to save battery/API calls
                if self.daytimeService.isDaytime {
                    await self.refreshDisplayUVIndex()
                }
            }
        }

        // Also do an immediate refresh on start
        Task {
            await refreshDisplayUVIndex()
        }
    }

    /// Refreshes the displayUVIndex from the API
    /// Uses the combined endpoint to also update forecast
    private func refreshDisplayUVIndex() async {
        guard let location = LocationManager.shared.currentLocation else {
            print("⚠️ [UVTrackingViewModel] Cannot refresh UV: Location not available")
            return
        }

        // Check if we need to refresh (avoid redundant calls)
        if let lastRefresh = lastUVRefreshTime,
           Date().timeIntervalSince(lastRefresh) < 840 {  // 14 minutes (slightly under cache)
            print("⏳ [UVTrackingViewModel] UV refresh skipped - recently updated")
            return
        }

        do {
            let uvData = try await WeatherService.shared.getUVDataWithForecast(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            displayUVIndex = uvData.currentUV
            uvForecast = uvData.forecast
            lastUVRefreshTime = Date()

            print("🌤️ [UVTrackingViewModel] Display UV refreshed: \(String(format: "%.1f", uvData.currentUV)) (\(uvData.forecast.count) forecast points)")

            // Force UI update
            objectWillChange.send()
        } catch {
            print("❌ [UVTrackingViewModel] Failed to refresh display UV: \(error)")
        }
    }

    // MARK: - User Actions
    // MARK: - Sunscreen Tracking

    private func restoreSunscreenState() {
        // Restore from UserDefaults
        let isSunscreenActive = UserDefaults.standard.bool(forKey: "sunscreenActive")

        if isSunscreenActive, let appliedTimeInterval = UserDefaults.standard.object(forKey: "sunscreenAppliedTime") as? TimeInterval {
            let appliedTime = Date(timeIntervalSince1970: appliedTimeInterval)
            let elapsed = Date().timeIntervalSince(appliedTime)

            // Check if sunscreen is still valid (within protection duration)
            if elapsed < AppConfig.sunscreenProtectionDuration {
                sunscreenActive = true
                sunscreenAppliedTime = appliedTime
                print("☀️ [UVTrackingViewModel] Restored sunscreen state: \(Int((AppConfig.sunscreenProtectionDuration - elapsed) / 60)) minutes remaining")
            } else {
                // Expired - clear it
                clearExpiredSunscreen()
                print("⏰ [UVTrackingViewModel] Sunscreen expired - cleared state")
            }
        }
    }

    func applySunscreen() {
        sunscreenActive = true
        sunscreenAppliedTime = Date()
    }

    func clearExpiredSunscreen() {
        sunscreenActive = false
        sunscreenAppliedTime = nil
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

    // MARK: - Manual Override

    func setManualIndoorOverride(duration: TimeInterval = 900) {
        LocationManager.shared.setManualIndoorOverride(duration: duration)
    }

    func clearManualOverride() {
        LocationManager.shared.clearManualOverride()
    }

    var isManualOverrideActive: Bool {
        LocationManager.shared.isManualOverrideActive
    }

    var manualOverrideRemainingTime: TimeInterval? {
        LocationManager.shared.manualOverrideRemainingTime
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

        print("📊 [UVTrackingViewModel] Loading UV data for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        do {
            // Use combined API to get both current UV and forecast in one call
            let uvData = try await WeatherService.shared.getUVDataWithForecast(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            displayUVIndex = uvData.currentUV
            uvForecast = uvData.forecast
            lastUVRefreshTime = Date()

            print("✅ [UVTrackingViewModel] UV data loaded: UV=\(String(format: "%.1f", uvData.currentUV)), \(uvData.forecast.count) forecast points")

            // Force UI update
            objectWillChange.send()
        } catch {
            print("❌ [UVTrackingViewModel] Error loading UV data: \(error)")
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
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -6, to: endDate) ?? endDate

        do {
            // Load UV sessions for the date range
            let sessions = try await supabase.getUserSessionsInRange(
                userId: userId,
                startDate: startDate,
                endDate: endDate
            )
            uvHistory = processUVHistory(sessions: sessions, startDate: startDate, endDate: endDate)
            print("✅ [UVTrackingViewModel] Loaded UV history: \(uvHistory.count) days")
        } catch {
            print("❌ [UVTrackingViewModel] Error loading UV history: \(error)")
        }

        // Load Vitamin D history for the date range
        do {
            let vitaminDData = try await supabase.getVitaminDDataInRange(
                userId: userId,
                startDate: startDate,
                endDate: endDate
            )
            vitaminDHistory = processVitaminDHistory(vitaminDData: vitaminDData, startDate: startDate, endDate: endDate)
            print("✅ [UVTrackingViewModel] Loaded Vitamin D history: \(vitaminDHistory.count) days")
        } catch {
            print("❌ [UVTrackingViewModel] Error loading Vitamin D history: \(error)")
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

    private func processUVHistory(sessions: [UVSession], startDate: Date, endDate: Date) -> [UVHistoryDay] {
        // Group sessions by day and create history entries for all 7 days
        var history: [UVHistoryDay] = []
        let calendar = Calendar.current

        // Generate all dates in the range
        var currentDate = startDate
        while currentDate <= endDate {
            let daySessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: currentDate) }
            let totalSED = daySessions.reduce(0) { $0 + $1.sessionSED }
            let medInSED = Double(profile?.med ?? 300) / 100.0
            let isSafe = totalSED < medInSED

            history.append(UVHistoryDay(
                date: currentDate,
                totalSED: totalSED,
                isSafe: isSafe,
                sessionCount: daySessions.count
            ))

            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return history
    }

    private func processVitaminDHistory(vitaminDData: [VitaminDData], startDate: Date, endDate: Date) -> [VitaminDHistoryDay] {
        // Create history entries for all 7 days
        var history: [VitaminDHistoryDay] = []
        let calendar = Calendar.current

        // Generate all dates in the range
        var currentDate = startDate
        while currentDate <= endDate {
            // Find vitamin D data for this day
            if let dayData = vitaminDData.first(where: { calendar.isDate($0.date, inSameDayAs: currentDate) }) {
                history.append(VitaminDHistoryDay(
                    date: currentDate,
                    totalIU: dayData.totalIU,
                    targetReached: dayData.targetReached
                ))
            } else {
                // No data for this day - show 0 IU
                history.append(VitaminDHistoryDay(
                    date: currentDate,
                    totalIU: 0,
                    targetReached: false
                ))
            }

            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return history
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
