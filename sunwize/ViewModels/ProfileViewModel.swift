import Foundation
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profile: Profile
    @Published var streaks: Streaks?
    @Published var featureSettings: FeatureSettings?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared
    private var cancellables = Set<AnyCancellable>()

    init(profile: Profile) {
        self.profile = profile
        Task {
            await loadUserData()
        }
    }

    // MARK: - Data Loading

    func loadUserData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load streaks
            streaks = try await supabase.getStreaks(userId: profile.id)
            if streaks == nil {
                // Create default streaks if none exist
                let newStreaks = Streaks(
                    id: UUID(),
                    userId: profile.id,
                    uvSafeStreak: 0,
                    vitaminDStreak: 0,
                    lastUpdated: Date()
                )
                try await supabase.createStreaks(newStreaks)
                streaks = newStreaks
            }

            // Load feature settings
            featureSettings = try await supabase.getFeatureSettings(userId: profile.id)
            if featureSettings == nil {
                // Create default settings if none exist
                let newSettings = FeatureSettings(
                    id: UUID(),
                    userId: profile.id,
                    uvTrackingEnabled: true,
                    vitaminDTrackingEnabled: true,
                    bodyScanRemindersEnabled: true,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try await supabase.createFeatureSettings(newSettings)
                featureSettings = newSettings
            }
        } catch {
            errorMessage = "Failed to load user data: \(error.localizedDescription)"
            print("Error loading user data: \(error)")
        }

        isLoading = false
    }

    // MARK: - Profile Updates

    func updateProfile(_ updatedProfile: Profile) async throws {
        try await supabase.updateProfile(updatedProfile)
        self.profile = updatedProfile
    }

    func updateFeatureSettings(_ settings: FeatureSettings) async throws {
        try await supabase.updateFeatureSettings(settings)
        self.featureSettings = settings
    }

    // MARK: - Statistics

    func getTotalUVExposureToday() async -> Double {
        do {
            let sessions = try await supabase.getUserSessions(userId: profile.id, date: Date())
            return sessions.reduce(0) { $0 + $1.sessionSED }
        } catch {
            print("Error fetching UV exposure: \(error)")
            return 0
        }
    }

    func getVitaminDToday() async -> Double {
        do {
            let data = try await supabase.getVitaminDData(userId: profile.id, date: Date())
            return data?.totalIU ?? 0
        } catch {
            print("Error fetching Vitamin D: \(error)")
            return 0
        }
    }
}
