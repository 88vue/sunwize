import Foundation
import SwiftUI
import AuthenticationServices
import Combine
import CoreLocation

// MARK: - Authentication State
enum AuthenticationState {
    case signedOut
    case signedIn(Profile)
    case onboarding(String) // email during onboarding
}

// MARK: - Authentication Service
@MainActor
class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()

    @Published var authState: AuthenticationState = .signedOut
    @Published var currentProfile: Profile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let supabase = SupabaseManager.shared

    override init() {
        super.init()
        checkAuthStatus()
    }

    // MARK: - Auth Status Check

    func checkAuthStatus() {
        Task {
            await MainActor.run { isLoading = true }

            // Check for stored auth token
            if let token = UserDefaults.standard.string(forKey: "auth_token"),
               let userId = UserDefaults.standard.string(forKey: "user_id"),
               let uuid = UUID(uuidString: userId) {

                do {
                    if let profile = try await supabase.getProfile(userId: uuid) {
                        await MainActor.run {
                            self.currentProfile = profile
                            if profile.onboardingCompleted {
                                self.authState = .signedIn(profile)
                            } else {
                                self.authState = .onboarding(profile.email)
                            }
                        }
                        
                        // IMMEDIATELY initialize location services if user is signed in
                        if profile.onboardingCompleted {
                            print("✅ [AuthService] User already signed in - initializing location services")
                            await initializeLocationServicesAfterAuth()
                        }
                    }
                } catch {
                    print("Error fetching profile: \(error)")
                    await MainActor.run {
                        self.authState = .signedOut
                    }
                }
            }

            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Email Authentication

    func signIn(email: String, password: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let profile = try await supabase.signIn(email: email, password: password)

            // Store auth info
            UserDefaults.standard.set(profile.id.uuidString, forKey: "user_id")
            // Note: In production, store auth token securely in Keychain

            await MainActor.run {
                self.currentProfile = profile
                if profile.onboardingCompleted {
                    self.authState = .signedIn(profile)
                } else {
                    self.authState = .onboarding(email)
                }
                self.isLoading = false
            }
            
            // IMMEDIATELY initialize location services after sign in if onboarding completed
            if profile.onboardingCompleted {
                print("✅ [AuthService] Sign in completed - initializing location services")
                await initializeLocationServicesAfterAuth()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            throw error
        }
    }

    func signUp(email: String, password: String, name: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            try await supabase.signUp(email: email, password: password, name: name)

            await MainActor.run {
                self.authState = .onboarding(email)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
            throw error
        }
    }

    // MARK: - Sign in with Apple

    func handleSignInWithApple(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return
            }

            let userIdentifier = appleIDCredential.user
            let fullName = appleIDCredential.fullName
            let email = appleIDCredential.email ?? ""

            // Save user identifier for future use
            UserDefaults.standard.set(userIdentifier, forKey: "apple_user_identifier")

            Task {
                do {
                    // Here you would integrate with Supabase's Apple Auth
                    // For now, we'll create a mock profile
                    let name = [fullName?.givenName, fullName?.familyName]
                        .compactMap { $0 }
                        .joined(separator: " ")

                    if !name.isEmpty && !email.isEmpty {
                        try await signUp(email: email, password: UUID().uuidString, name: name)
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
                    }
                }
            }

        case .failure(let error):
            errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Profile Management

    func completeOnboarding(profile: Profile) async throws {
        var updatedProfile = profile
        updatedProfile.onboardingCompleted = true

        try await supabase.updateProfile(updatedProfile)

        await MainActor.run {
            self.currentProfile = updatedProfile
            self.authState = .signedIn(updatedProfile)
        }
        
        // IMMEDIATELY request location and start tracking after onboarding
        print("✅ [AuthService] Onboarding completed - initializing location services")
        await initializeLocationServicesAfterAuth()
    }

    func updateProfile(_ profile: Profile) async throws {
        try await supabase.updateProfile(profile)

        await MainActor.run {
            self.currentProfile = profile
            if case .signedIn = authState {
                self.authState = .signedIn(profile)
            }
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.signOut()
        } catch {
            print("Sign out error: \(error)")
        }

        // Clear stored credentials
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "apple_user_identifier")

        await MainActor.run {
            self.currentProfile = nil
            self.authState = .signedOut
            self.errorMessage = nil
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        // Implement password reset via Supabase
        // This would send a password reset email
    }
    
    // MARK: - Location Services Initialization
    
    /// Initialize location services immediately after authentication
    private func initializeLocationServicesAfterAuth() async {
        let locationManager = LocationManager.shared
        let daytimeService = DaytimeService.shared
        
        // Step 1: Request "Always" location permission (required for background tracking)
        let currentAuth = CLLocationManager.authorizationStatus()
        if currentAuth != .authorizedAlways {
            await MainActor.run {
                print("📍 [AuthService] Requesting ALWAYS location permission for background tracking...")
                locationManager.requestLocationPermission()
            }
            
            // Wait for permission dialog response (longer for "Always" upgrade)
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            // Check if user granted permission
            let newAuth = CLLocationManager.authorizationStatus()
            if newAuth == .authorizedAlways {
                print("✅ [AuthService] ALWAYS location permission granted")
            } else if newAuth == .authorizedWhenInUse {
                print("⚠️ [AuthService] Only 'When In Use' granted - requesting upgrade to ALWAYS...")
                // iOS will show second dialog to upgrade to Always
                await MainActor.run {
                    locationManager.locationManagerInstance.requestAlwaysAuthorization()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            } else {
                print("❌ [AuthService] Location permission denied")
            }
        } else {
            print("✅ [AuthService] ALWAYS location permission already granted")
        }
        
        // Step 2: Get current location (one-time request)
        if locationManager.isAuthorized {
            await MainActor.run {
                print("📍 [AuthService] Requesting current location for sun times and UV forecast...")
                locationManager.requestOneTimeLocation()
            }
            
            // Wait for location update (longer to ensure GPS lock)
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            // Step 3: Update sun times with current location
            if let location = await MainActor.run(body: { locationManager.currentLocation }) {
                print("☀️ [AuthService] Got location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                print("☀️ [AuthService] Updating sun times...")
                await daytimeService.updateSunTimes(location: location)
                
                // CRITICAL: Trigger UV forecast load immediately
                print("📊 [AuthService] Triggering UV forecast load...")
                // The ViewModel subscription should catch this, but we'll verify
            } else {
                print("⚠️ [AuthService] Could not get location after 3 seconds - retrying...")
                // Retry once more
                await MainActor.run {
                    locationManager.requestOneTimeLocation()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                if let location = await MainActor.run(body: { locationManager.currentLocation }) {
                    print("✅ [AuthService] Got location on retry: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    await daytimeService.updateSunTimes(location: location)
                } else {
                    print("❌ [AuthService] Still no location - user may need to enable location services")
                }
            }
            
            // Step 4: Start location tracking if daytime
            await MainActor.run {
                if daytimeService.isDaytime {
                    if !locationManager.isTracking {
                        print("🌞 [AuthService] Daytime - starting continuous location tracking")
                        locationManager.startLocationUpdates()
                    }
                } else {
                    print("🌙 [AuthService] Nighttime - location tracking will start at sunrise")
                }
            }
        } else {
            print("❌ [AuthService] Location permission not granted - UV tracking disabled")
            print("   User must enable location in Settings → Sunwize → Location → Always")
        }
    }
}

// MARK: - Sign in with Apple Button
struct SignInWithAppleButton: View {
    @StateObject private var authService = AuthenticationService.shared

    var body: some View {
        SignInWithAppleButtonRepresentable(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                authService.handleSignInWithApple(result: result)
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
    }
}

// MARK: - SwiftUI Representable for Sign in with Apple
import SwiftUI

struct SignInWithAppleButtonRepresentable: UIViewRepresentable {
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .black
        )
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleSignInWithApple),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: SignInWithAppleButtonRepresentable

        init(_ parent: SignInWithAppleButtonRepresentable) {
            self.parent = parent
        }

        @objc func handleSignInWithApple() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            parent.onRequest(request)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            parent.onCompletion(.success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            parent.onCompletion(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}