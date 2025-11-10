import SwiftUI

struct RootView: View {
    @EnvironmentObject var authService: AuthenticationService

    var body: some View {
        Group {
            switch authService.authState {
            case .signedOut:
                OnboardingContainerView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .onboarding(let email):
                OnboardingContainerView(startingStep: .profile, email: email)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .signedIn(let profile):
                MainTabView()
                    .environmentObject(ProfileViewModel(profile: profile))
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.authState.id)
    }
}

// Extension to make AuthenticationState identifiable for animation
extension AuthenticationState {
    var id: String {
        switch self {
        case .signedOut:
            return "signedOut"
        case .onboarding(let email):
            return "onboarding_\(email)"
        case .signedIn(let profile):
            return "signedIn_\(profile.id.uuidString)"
        }
    }
}