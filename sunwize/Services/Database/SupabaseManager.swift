import Foundation
import Combine
import Supabase

// MARK: - Supabase Manager
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    // Supabase client instance
    let client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws -> Profile {
        // Sign in with Supabase Auth
        let session = try await client.auth.signIn(email: email, password: password)
        
        // Store session
        UserDefaults.standard.set(session.accessToken, forKey: "auth_token")
        UserDefaults.standard.set(session.user.id.uuidString, forKey: "user_id")
        
        // Fetch user profile
        guard let profile = try await getProfile(userId: session.user.id) else {
            throw NSError(domain: "SupabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Profile not found"])
        }
        
        return profile
    }

    func signUp(email: String, password: String, name: String) async throws {
        // Sign up with Supabase Auth
        let authResponse = try await client.auth.signUp(email: email, password: password)
        
        // Create profile record
        let newProfile = Profile(
            id: authResponse.user.id,
            email: email,
            name: name,
            age: 25,
            gender: .preferNotToSay,
            skinType: 2,
            med: 300,
            onboardingCompleted: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await client.from("profiles")
            .insert(newProfile)
            .execute()
        
        // Store session if available
        if let session = authResponse.session {
            UserDefaults.standard.set(session.accessToken, forKey: "auth_token")
        }
        UserDefaults.standard.set(authResponse.user.id.uuidString, forKey: "user_id")
    }

    func signOut() async throws {
        try await client.auth.signOut()
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
    }
    
    func getCurrentSession() async throws -> Session? {
        return try await client.auth.session
    }

    // MARK: - Profile Operations

    func getProfile(userId: UUID) async throws -> Profile? {
        let response: [Profile] = try await client.from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }

    func updateProfile(_ profile: Profile) async throws {
        try await client.from("profiles")
            .update(profile)
            .eq("id", value: profile.id.uuidString)
            .execute()
    }

    // MARK: - UV Sessions

    func createUVSession(_ session: UVSession) async throws {
        try await client.from("uv_sessions")
            .insert(session)
            .execute()
    }

    func updateUVSession(_ session: UVSession) async throws {
        try await client.from("uv_sessions")
            .update(session)
            .eq("id", value: session.id.uuidString)
            .execute()
    }

    func getUserSessions(userId: UUID, date: Date) async throws -> [UVSession] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: date)

        let response: [UVSession] = try await client.from("uv_sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("date", value: dateString)
            .execute()
            .value
        
        return response
    }

    // MARK: - Vitamin D Data

    func getVitaminDData(userId: UUID, date: Date) async throws -> VitaminDData? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: date)

        let response: [VitaminDData] = try await client.from("vitamin_d_data")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("date", value: dateString)
            .execute()
            .value
        
        return response.first
    }

    func updateVitaminDData(_ data: VitaminDData) async throws {
        try await client.from("vitamin_d_data")
            .update(data)
            .eq("id", value: data.id.uuidString)
            .execute()
    }
    
    func createVitaminDData(_ data: VitaminDData) async throws {
        try await client.from("vitamin_d_data")
            .insert(data)
            .execute()
    }

    // MARK: - Body Scans

    func getBodyLocations(userId: UUID) async throws -> [BodyLocation] {
        let response: [BodyLocation] = try await client.from("body_location")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        return response
    }

    func createBodyLocation(_ location: BodyLocation) async throws -> BodyLocation {
        let response: [BodyLocation] = try await client.from("body_location")
            .insert(location)
            .select()
            .execute()
            .value
        
        guard let created = response.first else {
            throw NSError(domain: "SupabaseManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create body location"])
        }
        
        return created
    }

    func getBodySpots(locationId: UUID) async throws -> [BodySpot] {
        let response: [BodySpot] = try await client.from("body_spots")
            .select()
            .eq("location_id", value: locationId.uuidString)
            .execute()
            .value
        
        return response
    }

    func createBodySpot(_ spot: BodySpot) async throws {
        try await client.from("body_spots")
            .insert(spot)
            .execute()
    }
    
    func deleteBodySpot(_ spotId: UUID) async throws {
        try await client.from("body_spots")
            .delete()
            .eq("id", value: spotId.uuidString)
            .execute()
    }
    
    func deleteImage(bucket: String, path: String) async throws {
        try await client.storage
            .from(bucket)
            .remove(paths: [path])
    }

    // MARK: - Streaks

    func getStreaks(userId: UUID) async throws -> Streaks? {
        let response: [Streaks] = try await client.from("streaks")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }

    func updateStreaks(_ streaks: Streaks) async throws {
        try await client.from("streaks")
            .update(streaks)
            .eq("id", value: streaks.id.uuidString)
            .execute()
    }
    
    func createStreaks(_ streaks: Streaks) async throws {
        try await client.from("streaks")
            .insert(streaks)
            .execute()
    }
    
    // MARK: - Feature Settings
    
    func getFeatureSettings(userId: UUID) async throws -> FeatureSettings? {
        let response: [FeatureSettings] = try await client.from("feature_settings")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }
    
    func updateFeatureSettings(_ settings: FeatureSettings) async throws {
        try await client.from("feature_settings")
            .update(settings)
            .eq("id", value: settings.id.uuidString)
            .execute()
    }
    
    func createFeatureSettings(_ settings: FeatureSettings) async throws {
        try await client.from("feature_settings")
            .insert(settings)
            .execute()
    }
}
