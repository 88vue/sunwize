import Foundation
import BackgroundTasks
import CoreLocation
import Combine

// MARK: - Background Task Manager (Facade)

/// Facade for the refactored UV tracking system
/// Provides backward compatible API while delegating to modular services
@MainActor
class BackgroundTaskManager: NSObject, ObservableObject {
    static let shared = BackgroundTaskManager()

    // MARK: - Services

    private let uvTrackingManager = UVTrackingManager.shared
    private let sessionStore = UVSessionStore.shared
    private let notificationService = UVNotificationService.shared
    private let backgroundTaskService = BackgroundTaskService.shared
    private let supabase = SupabaseManager.shared

    // MARK: - Published State (Backward Compatible)

    @Published private(set) var isUVTrackingActive: Bool = false
    @Published private(set) var currentSessionSED: Double = 0.0
    @Published private(set) var currentSessionStartTime: Date?
    @Published private(set) var currentExposureRatio: Double = 0.0
    @Published private(set) var currentVitaminD: Double = 0.0
    @Published private(set) var vitaminDProgress: Double = 0.0

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lock State (Backward Compatible)

    var outdoorLockActive: Bool { uvTrackingManager.outdoorLockActive }
    var vehicleLockActive: Bool { uvTrackingManager.vehicleLockActive }

    // MARK: - Initialization

    private override init() {
        super.init()
        setupBackgroundTaskCallbacks()
        setupServiceForwarding()
    }

    private func setupServiceForwarding() {
        // Forward published values from UVTrackingManager
        uvTrackingManager.$isUVTrackingActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.isUVTrackingActive = active
            }
            .store(in: &cancellables)

        // Forward published values from UVSessionStore
        sessionStore.$currentSessionSED
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sed in
                self?.currentSessionSED = sed
            }
            .store(in: &cancellables)

        sessionStore.$currentSessionStartTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] startTime in
                self?.currentSessionStartTime = startTime
            }
            .store(in: &cancellables)

        sessionStore.$currentExposureRatio
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ratio in
                self?.currentExposureRatio = ratio
            }
            .store(in: &cancellables)

        sessionStore.$currentVitaminD
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vitD in
                self?.currentVitaminD = vitD
            }
            .store(in: &cancellables)

        sessionStore.$vitaminDProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.vitaminDProgress = progress
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    func registerBackgroundTasks() {
        backgroundTaskService.registerBackgroundTasks()
        print("[BackgroundTaskManager] Background tasks registered")
    }

    func scheduleBackgroundTasks() {
        backgroundTaskService.scheduleBackgroundTasks()
    }

    private func setupBackgroundTaskCallbacks() {
        backgroundTaskService.onUVTrackingTask = { [weak self] in
            await self?.handleUVTrackingTask()
        }

        backgroundTaskService.onDailyMaintenanceTask = { [weak self] in
            await self?.handleDailyMaintenanceTask()
        }

        backgroundTaskService.onAppRefreshTask = { [weak self] in
            await self?.handleAppRefreshTask()
        }
    }

    // MARK: - Backward Compatible API

    /// Called by LocationManager when outdoor mode is detected
    func handleOutsideDetection(location: CLLocation, state: LegacyLocationState) async {
        let locationManager = LocationManager.shared

        await uvTrackingManager.handleOutsideDetection(
            location: location,
            state: state,
            isManualOverrideActive: locationManager.isManualOverrideActive,
            nearestBuildingDistance: locationManager.getCachedNearestBuildingDistance(),
            isInsidePolygon: locationManager.isInsideAnyPolygon(),
            hasRecentPolygonExit: locationManager.hasRecentPolygonExit().0,
            hasExcellentGPS: (state.accuracy ?? 100) < 15
        )
    }

    /// Called by LocationManager when indoor/vehicle mode is detected
    func handleInsideDetection(state: LegacyLocationState) async {
        let locationManager = LocationManager.shared

        await uvTrackingManager.handleInsideDetection(
            state: state,
            nearestBuildingDistance: locationManager.getCachedNearestBuildingDistance(),
            isInsidePolygon: locationManager.isInsideAnyPolygon()
        )
    }

    // MARK: - Backward Compatible Methods (called from app)

    /// Check for day change and reset daily counters if needed
    func checkForDayChange() async {
        guard let userId = await getCurrentUserId() else { return }
        try? await sessionStore.loadVitaminD(userId: userId)
    }

    /// Sync Vitamin D to database
    func syncVitaminDToDatabase() async {
        try? await sessionStore.syncVitaminDToDatabase()
    }

    // MARK: - Background Task Handlers

    private func handleUVTrackingTask() async {
        guard await shouldTrackUV() else { return }

        // UV tracking is handled by UVTrackingManager via location updates
        print("[BackgroundTaskManager] UV tracking task completed")
    }

    private func handleDailyMaintenanceTask() async {
        do {
            // End any active session
            if sessionStore.isSessionActive {
                try await sessionStore.endSession()
            }

            // Sync Vitamin D to database
            try await sessionStore.syncVitaminDToDatabase()

            // Update streaks
            try await updateStreaks()

            // Reset daily counters
            await uvTrackingManager.resetDailyState()

            // Schedule morning UV notification
            await scheduleMorningUVNotification()

            print("[BackgroundTaskManager] Daily maintenance completed")
        } catch {
            print("[BackgroundTaskManager] Daily maintenance error: \(error)")
        }
    }

    private func handleAppRefreshTask() async {
        // Verify location tracking is still active
        let locationManager = LocationManager.shared
        if !locationManager.isTracking {
            print("[BackgroundTaskManager] Location tracking stopped - restarting")
            locationManager.startLocationUpdates()
        }

        // Force location check
        _ = try? await locationManager.getCurrentState(forceRefresh: true)
    }

    // MARK: - UV Tracking Check

    private func shouldTrackUV() async -> Bool {
        guard let userId = await getCurrentUserId(),
              let settings = try? await supabase.getFeatureSettings(userId: userId),
              settings.uvTrackingEnabled else {
            return false
        }

        guard DaytimeService.shared.isDaytime else { return false }

        return LocationManager.shared.locationMode == .outside
    }

    // MARK: - Streak Updates

    private func updateStreaks() async throws {
        guard let userId = await getCurrentUserId(),
              let profile = try? await supabase.getProfile(userId: userId) else {
            return
        }

        // Get today's sessions
        let sessions = try await supabase.getUserSessions(userId: userId, date: Date())

        // Check UV safe streak
        let totalSED = sessions.reduce(0) { $0 + $1.sessionSED }
        let medInSED = Double(profile.med) / 100.0
        let isUVSafe = totalSED < medInSED

        // Check Vitamin D streak
        let vitaminDReached = sessionStore.dailyVitaminD?.targetReached ?? false

        // Update streaks
        if var streaks = try await supabase.getStreaks(userId: userId) {
            if isUVSafe {
                streaks.uvSafeStreak += 1
            } else {
                streaks.uvSafeStreak = 0
            }

            if vitaminDReached {
                streaks.vitaminDStreak += 1
            } else {
                streaks.vitaminDStreak = 0
            }

            try await supabase.updateStreaks(streaks)
        }

        print("[BackgroundTaskManager] Streaks updated")
    }

    // MARK: - Morning UV Notification

    private func scheduleMorningUVNotification() async {
        guard let location = LocationService.shared.currentLocation else {
            print("[BackgroundTaskManager] Cannot schedule morning notification: No location")
            return
        }

        do {
            let forecast = try await WeatherService.shared.getUVForecast(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            // Filter to tomorrow's forecast
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let tomorrowStart = calendar.startOfDay(for: tomorrow)
            let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart

            let tomorrowForecast = forecast.filter {
                $0.time >= tomorrowStart && $0.time < tomorrowEnd
            }

            if let peakData = tomorrowForecast.max(by: { $0.uvIndex < $1.uvIndex }) {
                let timeFormatter = DateFormatter()
                timeFormatter.timeStyle = .short
                let peakTimeString = timeFormatter.string(from: peakData.time)

                await notificationService.scheduleMorningUVPeakNotification(
                    peakUVTime: peakTimeString,
                    peakUVIndex: peakData.uvIndex
                )
            }
        } catch {
            print("[BackgroundTaskManager] Failed to schedule morning notification: \(error)")
        }
    }

    // MARK: - Helpers

    private func getCurrentUserId() async -> UUID? {
        // Get from auth service or stored credentials
        guard let userIdString = UserDefaults.standard.string(forKey: "user_id"),
              let userId = UUID(uuidString: userIdString) else {
            return nil
        }
        return userId
    }

    // MARK: - App Lifecycle

    /// Called when app enters background
    func applicationDidEnterBackground() {
        backgroundTaskService.scheduleBackgroundTasks()

        // Sync Vitamin D before backgrounding
        Task {
            try? await sessionStore.syncVitaminDToDatabase()
        }
    }

    /// Called when app becomes active
    func applicationDidBecomeActive() {
        // Refresh UV tracking state
        Task {
            _ = try? await LocationManager.shared.getCurrentState(forceRefresh: true)
        }
    }
}
