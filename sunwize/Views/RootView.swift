import SwiftUI

struct RootView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var profileViewModel = ProfileViewModelContainer()

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
                    .environmentObject(profileViewModel.getViewModel(for: profile))
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.authState.id)
    }
}

// MARK: - ProfileViewModel Container
// Wrapper to manage ProfileViewModel lifecycle and prevent recreation on every state change
@MainActor
class ProfileViewModelContainer: ObservableObject {
    private var viewModel: ProfileViewModel?
    private var currentProfileId: UUID?

    func getViewModel(for profile: Profile) -> ProfileViewModel {
        // Only create new ViewModel if profile changed or doesn't exist
        if viewModel == nil || currentProfileId != profile.id {
            viewModel = ProfileViewModel(profile: profile)
            currentProfileId = profile.id
        } else if viewModel?.profile.id == profile.id {
            // Update existing ViewModel with latest profile data
            viewModel?.profile = profile
        }

        return viewModel!
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