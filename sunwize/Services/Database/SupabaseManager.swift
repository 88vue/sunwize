import Foundation
import Combine
import Supabase

// MARK: - Supabase Manager
/// Manages all Supabase database operations with custom date handling
///
/// DATE HANDLING STRATEGY:
/// - Database stores DATE columns as "2025-11-11" (date-only, no time)
/// - Database stores TIMESTAMPTZ columns as "2025-11-11T10:30:00Z" (with time)
/// - **READS**: Use custom decoder on response.data to handle both formats
/// - **WRITES**: Let Supabase SDK handle encoding (it converts Swift Date to proper format)
/// - This fixes the "Invalid date format: 2025-11-11" error when loading UV/Vitamin D history
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    // Supabase client instance
    let client: SupabaseClient

    // Custom JSON decoder for handling multiple date formats from Supabase
    // Supports: ISO8601 with time, ISO8601 date-only, and fractional seconds
    // Used when decoding response.data from GET requests
    static let customDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with time first (e.g., "2025-11-11T10:30:00Z")
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try date-only format (e.g., "2025-11-11") - CRITICAL FOR UV/VITAMIN D DATA
            iso8601Formatter.formatOptions = [.withFullDate]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
    }()

    private init() {
        // Create client with custom configuration
        // Note: The Supabase Swift SDK doesn't support global encoder/decoder config
        // We'll handle encoding/decoding manually in each operation
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

        // Insert profile directly - Supabase SDK will handle encoding
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
        // Get raw data and decode with custom decoder
        let response = try await client.from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()

        let profiles = try SupabaseManager.customDecoder.decode([Profile].self, from: response.data)
        return profiles.first
    }

    func updateProfile(_ profile: Profile) async throws {
        // Update profile directly - Supabase SDK will handle encoding
        try await client.from("profiles")
            .update(profile)
            .eq("id", value: profile.id.uuidString)
            .execute()
    }

    // MARK: - UV Sessions

    func createUVSession(_ session: UVSession) async throws {
        // Insert session directly - Supabase SDK will handle encoding
        try await client.from("uv_sessions")
            .insert(session)
            .execute()
    }

    func updateUVSession(_ session: UVSession) async throws {
        // Update session directly - Supabase SDK will handle encoding
        try await client.from("uv_sessions")
            .update(session)
            .eq("id", value: session.id.uuidString)
            .execute()
    }

    func getUserSessions(userId: UUID, date: Date) async throws -> [UVSession] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: date)

        // Get raw data and decode with custom decoder
        let response = try await client.from("uv_sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("date", value: dateString)
            .execute()

        let sessions = try SupabaseManager.customDecoder.decode([UVSession].self, from: response.data)
        return sessions
    }

    func getUserSessionsInRange(userId: UUID, startDate: Date, endDate: Date) async throws -> [UVSession] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        // Get raw data and decode with custom decoder
        let response = try await client.from("uv_sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startDateString)
            .lte("date", value: endDateString)
            .order("date", ascending: true)
            .execute()

        let sessions = try SupabaseManager.customDecoder.decode([UVSession].self, from: response.data)
        return sessions
    }

    // MARK: - Vitamin D Data

    func getVitaminDData(userId: UUID, date: Date) async throws -> VitaminDData? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: date)

        // Get raw data and decode with custom decoder
        let response = try await client.from("vitamin_d_data")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("date", value: dateString)
            .execute()

        let data = try SupabaseManager.customDecoder.decode([VitaminDData].self, from: response.data)
        return data.first
    }

    func updateVitaminDData(_ data: VitaminDData) async throws {
        // Update data directly - Supabase SDK will handle encoding
        try await client.from("vitamin_d_data")
            .update(data)
            .eq("id", value: data.id.uuidString)
            .execute()
    }

    func createVitaminDData(_ data: VitaminDData) async throws {
        // Insert data directly - Supabase SDK will handle encoding
        try await client.from("vitamin_d_data")
            .insert(data)
            .execute()
    }

    func getVitaminDDataInRange(userId: UUID, startDate: Date, endDate: Date) async throws -> [VitaminDData] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        // Get raw data and decode with custom decoder
        let response = try await client.from("vitamin_d_data")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startDateString)
            .lte("date", value: endDateString)
            .order("date", ascending: true)
            .execute()

        let data = try SupabaseManager.customDecoder.decode([VitaminDData].self, from: response.data)
        return data
    }

    // MARK: - Body Spots

    func getBodyLocations(userId: UUID) async throws -> [BodyLocation] {
        // Get raw data and decode with custom decoder
        let response = try await client.from("body_location")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()

        let locations = try SupabaseManager.customDecoder.decode([BodyLocation].self, from: response.data)
        return locations
    }

    func createBodyLocation(_ location: BodyLocation) async throws -> BodyLocation {
        // Get raw data and decode with custom decoder
        let response = try await client.from("body_location")
            .insert(location)
            .select()
            .execute()

        let locations = try SupabaseManager.customDecoder.decode([BodyLocation].self, from: response.data)
        guard let created = locations.first else {
            throw NSError(domain: "SupabaseManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create body location"])
        }

        return created
    }

    func getBodySpots(locationId: UUID) async throws -> [BodySpot] {
        // Get raw data and decode with custom decoder
        let response = try await client.from("body_spots")
            .select()
            .eq("location_id", value: locationId.uuidString)
            .execute()

        let spots = try SupabaseManager.customDecoder.decode([BodySpot].self, from: response.data)
        return spots
    }

    func createBodySpot(_ spot: BodySpot) async throws {
        // Insert spot directly - Supabase SDK will handle encoding
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
        // Get raw data and decode with custom decoder
        let response = try await client.from("streaks")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()

        let streaks = try SupabaseManager.customDecoder.decode([Streaks].self, from: response.data)
        return streaks.first
    }

    func updateStreaks(_ streaks: Streaks) async throws {
        // Update streaks directly - Supabase SDK will handle encoding
        try await client.from("streaks")
            .update(streaks)
            .eq("id", value: streaks.id.uuidString)
            .execute()
    }

    func createStreaks(_ streaks: Streaks) async throws {
        // Insert streaks directly - Supabase SDK will handle encoding
        try await client.from("streaks")
            .insert(streaks)
            .execute()
    }
    
    // MARK: - Feature Settings
    
    func getFeatureSettings(userId: UUID) async throws -> FeatureSettings? {
        // Get raw data and decode with custom decoder
        let response = try await client.from("feature_settings")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()

        let settings = try SupabaseManager.customDecoder.decode([FeatureSettings].self, from: response.data)
        return settings.first
    }
    
    func updateFeatureSettings(_ settings: FeatureSettings) async throws {
        // Update settings directly - Supabase SDK will handle encoding
        try await client.from("feature_settings")
            .update(settings)
            .eq("id", value: settings.id.uuidString)
            .execute()
    }

    func createFeatureSettings(_ settings: FeatureSettings) async throws {
        // Insert settings directly - Supabase SDK will handle encoding
        try await client.from("feature_settings")
            .insert(settings)
            .execute()
    }
}
