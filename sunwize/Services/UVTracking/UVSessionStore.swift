import Foundation

// MARK: - UV Session Store

/// Manages UV session persistence and lifecycle
@MainActor
class UVSessionStore: ObservableObject {
    static let shared = UVSessionStore()

    // MARK: - Services

    private let supabase = SupabaseManager.shared

    // MARK: - Current Session

    @Published private(set) var currentSession: UVSession?
    @Published private(set) var dailyVitaminD: VitaminDData?

    // MARK: - Published State

    @Published private(set) var currentSessionSED: Double = 0.0
    @Published private(set) var currentSessionStartTime: Date?
    @Published private(set) var currentExposureRatio: Double = 0.0
    @Published private(set) var currentVitaminD: Double = 0.0
    @Published private(set) var vitaminDProgress: Double = 0.0

    // MARK: - Internal State

    private var lastSEDUpdateTime: Date?
    private var lastKnownDate: Date?
    private var lastVitaminDSyncTime: Date?
    private let vitaminDSyncInterval: TimeInterval = 120 // Sync every 2 minutes

    // MARK: - Sunscreen Keys

    private let sunscreenStateKey = "sunscreenActive"
    private let sunscreenTimeKey = "sunscreenAppliedTime"

    // MARK: - Initialization

    private init() {}

    // MARK: - Session Lifecycle

    /// Start a new UV session
    func startSession(userId: UUID) async throws {
        let sunscreenActive = isSunscreenActive()
        let sessionStart = Date()

        let session = UVSession(
            id: UUID(),
            userId: userId,
            date: sessionStart,
            startTime: sessionStart,
            endTime: nil,
            sessionSED: 0,
            sunscreenApplied: sunscreenActive,
            createdAt: sessionStart
        )

        try await supabase.createUVSession(session)

        currentSession = session
        lastSEDUpdateTime = sessionStart
        currentSessionStartTime = sessionStart
        currentSessionSED = 0.0
        currentExposureRatio = 0.0

        print("[UVSessionStore] New UV session created - ID: \(session.id)")
    }

    /// Update current session with new SED value
    func updateSession(sedIncrement: Double, userMED: Double) async throws {
        guard var session = currentSession else {
            print("[UVSessionStore] No active session to update")
            return
        }

        session.sessionSED += sedIncrement
        lastSEDUpdateTime = Date()

        try await supabase.updateUVSession(session)

        currentSession = session
        currentSessionSED = session.sessionSED
        currentExposureRatio = UVExposureCalculator.calculateExposureRatio(
            sessionSED: session.sessionSED,
            userMED: userMED
        )

        print("[UVSessionStore] Session updated - SED: \(String(format: "%.4f", session.sessionSED))")
    }

    /// End current UV session
    func endSession() async throws {
        guard var session = currentSession else { return }

        session.endTime = Date()
        try await supabase.updateUVSession(session)

        // Sync Vitamin D to database before clearing
        if let vitaminD = dailyVitaminD {
            try await supabase.updateVitaminDData(vitaminD)
        }

        currentSession = nil
        lastSEDUpdateTime = nil
        currentSessionStartTime = nil

        print("[UVSessionStore] Session ended - Total SED: \(String(format: "%.4f", session.sessionSED))")
    }

    /// Get time since last SED update
    func getTimeSinceLastUpdate() -> TimeInterval {
        guard let lastUpdate = lastSEDUpdateTime else {
            if let startTime = currentSession?.startTime {
                return Date().timeIntervalSince(startTime)
            }
            return 0
        }
        return Date().timeIntervalSince(lastUpdate)
    }

    /// Check if session is active
    var isSessionActive: Bool {
        currentSession != nil && currentSession?.endTime == nil
    }

    // MARK: - Vitamin D Management

    /// Load or create today's Vitamin D data
    func loadVitaminD(userId: UUID) async throws {
        // Check for day change first
        await checkForDayChange(userId: userId)

        if dailyVitaminD == nil {
            dailyVitaminD = try await supabase.getVitaminDData(userId: userId, date: Date())

            if dailyVitaminD == nil {
                let newData = VitaminDData(
                    id: UUID(),
                    userId: userId,
                    date: Date(),
                    totalIU: 0,
                    targetIU: AppConfig.defaultDailyVitaminDTarget,
                    bodyExposureFactor: 0.3,
                    createdAt: Date(),
                    updatedAt: Date()
                )

                try await supabase.createVitaminDData(newData)
                dailyVitaminD = newData
                print("[UVSessionStore] Created new Vitamin D record for today")
            }

            let progress = dailyVitaminD!.totalIU / dailyVitaminD!.targetIU
            currentVitaminD = dailyVitaminD!.totalIU
            vitaminDProgress = progress
        }
    }

    /// Update Vitamin D with increment
    func updateVitaminD(increment: Double) async throws {
        guard var vitaminD = dailyVitaminD else { return }

        vitaminD.totalIU += increment
        vitaminD.updatedAt = Date()

        dailyVitaminD = vitaminD

        let progress = vitaminD.totalIU / vitaminD.targetIU
        currentVitaminD = vitaminD.totalIU
        vitaminDProgress = progress

        print("[UVSessionStore] Vitamin D updated - Total: \(String(format: "%.1f", vitaminD.totalIU)) IU")

        // Periodic sync to database (every 2 minutes) to prevent data loss on crash
        let now = Date()
        if lastVitaminDSyncTime == nil || now.timeIntervalSince(lastVitaminDSyncTime!) >= vitaminDSyncInterval {
            try await syncVitaminDToDatabase()
            lastVitaminDSyncTime = now
        }
    }

    /// Sync Vitamin D to database
    func syncVitaminDToDatabase() async throws {
        guard let vitaminD = dailyVitaminD else { return }
        try await supabase.updateVitaminDData(vitaminD)
        print("[UVSessionStore] Vitamin D synced to database")
    }

    // MARK: - Day Change Detection

    private func checkForDayChange(userId: UUID) async {
        let today = Calendar.current.startOfDay(for: Date())

        if let lastDate = lastKnownDate {
            if !Calendar.current.isDate(lastDate, inSameDayAs: today) {
                // Day changed - save old data and reset
                if let vitaminD = dailyVitaminD {
                    try? await supabase.updateVitaminDData(vitaminD)
                    print("[UVSessionStore] Saved previous day's Vitamin D before reset")
                }

                dailyVitaminD = nil
                currentVitaminD = 0.0
                vitaminDProgress = 0.0

                print("[UVSessionStore] Day changed - reset daily Vitamin D")
            }
        }

        lastKnownDate = today
    }

    /// Force day change check and reset
    func resetDailyCounters() async {
        dailyVitaminD = nil
        currentVitaminD = 0.0
        vitaminDProgress = 0.0
        lastKnownDate = Calendar.current.startOfDay(for: Date())
        print("[UVSessionStore] Daily counters reset")
    }

    // MARK: - Sunscreen State

    func isSunscreenActive() -> Bool {
        return UserDefaults.standard.bool(forKey: sunscreenStateKey)
    }

    func getSunscreenAppliedTime() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: sunscreenTimeKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    func setSunscreenActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: sunscreenStateKey)
        if active {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: sunscreenTimeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sunscreenTimeKey)
        }
    }
}
