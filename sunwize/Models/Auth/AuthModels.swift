import Foundation

// MARK: - Auth Response Models

struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Codable {
    let id: UUID
    let aud: String
    let role: String
    let email: String
    let emailConfirmedAt: String?
    let phone: String?
    let confirmedAt: String?
    let lastSignInAt: String?
    let appMetadata: AppMetadata
    let userMetadata: UserMetadata
    let identities: [Identity]?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case aud
        case role
        case email
        case emailConfirmedAt = "email_confirmed_at"
        case phone
        case confirmedAt = "confirmed_at"
        case lastSignInAt = "last_sign_in_at"
        case appMetadata = "app_metadata"
        case userMetadata = "user_metadata"
        case identities
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AppMetadata: Codable {
    let provider: String?
    let providers: [String]?
}

struct UserMetadata: Codable {
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case avatarUrl = "avatar_url"
    }
}

struct Identity: Codable {
    let id: String
    let userId: UUID
    let identityData: IdentityData
    let provider: String
    let lastSignInAt: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case identityData = "identity_data"
        case provider
        case lastSignInAt = "last_sign_in_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct IdentityData: Codable {
    let email: String?
    let sub: String?
}

// MARK: - Auth Error Response

struct AuthErrorResponse: Codable {
    let error: String?
    let message: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message = "msg"
        case errorDescription = "error_description"
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidResponse
    case signInFailed(String)
    case signUpFailed(String)
    case profileNotFound
    case tokenExpired
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .signInFailed(let message):
            return message
        case .signUpFailed(let message):
            return message
        case .profileNotFound:
            return "User profile not found"
        case .tokenExpired:
            return "Session expired. Please sign in again"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}