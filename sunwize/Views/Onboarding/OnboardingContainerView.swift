import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case problem
    case solution
    case auth
    case profile
    case setup
    case permissions

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .problem:
            return "The Problem"
        case .solution:
            return "The Solution"
        case .auth:
            return "Sign In"
        case .profile:
            return "Your Profile"
        case .setup:
            return "Setup"
        case .permissions:
            return "Permissions"
        }
    }

    var next: OnboardingStep? {
        guard let index = OnboardingStep.allCases.firstIndex(of: self),
              index < OnboardingStep.allCases.count - 1 else { return nil }
        return OnboardingStep.allCases[index + 1]
    }

    var previous: OnboardingStep? {
        guard let index = OnboardingStep.allCases.firstIndex(of: self),
              index > 0 else { return nil }
        return OnboardingStep.allCases[index - 1]
    }
}

struct OnboardingContainerView: View {
    @State private var currentStep: OnboardingStep
    @State private var userEmail: String
    @State private var profileData = ProfileData()
    @EnvironmentObject var authService: AuthenticationService

    init(startingStep: OnboardingStep = .welcome, email: String = "") {
        _currentStep = State(initialValue: startingStep)
        _userEmail = State(initialValue: email)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.orange.opacity(0.3), Color.yellow.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack {
                    // Progress indicator
                    ProgressIndicator(currentStep: currentStep)
                        .padding(.horizontal)
                        .padding(.top)

                    // Content
                    TabView(selection: $currentStep) {
                        WelcomeView(onContinue: nextStep)
                            .tag(OnboardingStep.welcome)

                        ProblemView(onContinue: nextStep, onBack: previousStep)
                            .tag(OnboardingStep.problem)

                        SolutionView(onContinue: nextStep, onBack: previousStep)
                            .tag(OnboardingStep.solution)

                        AuthView(onSuccess: { email in
                            userEmail = email
                            nextStep()
                        }, onBack: previousStep)
                            .tag(OnboardingStep.auth)

                        ProfileSetupView(
                            profileData: $profileData,
                            onContinue: nextStep,
                            onBack: previousStep
                        )
                        .tag(OnboardingStep.profile)

                        PersonalizedSetupView(
                            profileData: profileData,
                            onContinue: nextStep,
                            onBack: previousStep
                        )
                        .tag(OnboardingStep.setup)

                        PermissionsView(onComplete: completeOnboarding)
                            .tag(OnboardingStep.permissions)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func nextStep() {
        withAnimation {
            if let next = currentStep.next {
                currentStep = next
            }
        }
    }

    private func previousStep() {
        withAnimation {
            if let previous = currentStep.previous {
                currentStep = previous
            }
        }
    }

    private func completeOnboarding() {
        Task {
            do {
                // Create and save complete profile
                let profile = Profile(
                    id: UUID(), // Will be replaced with actual user ID
                    email: userEmail,
                    name: profileData.name,
                    age: profileData.age,
                    gender: profileData.gender,
                    skinType: profileData.skinType,
                    med: profileData.calculatedMED,
                    onboardingCompleted: true,
                    createdAt: Date(),
                    updatedAt: Date()
                )

                try await authService.completeOnboarding(profile: profile)
            } catch {
                print("Error completing onboarding: \(error)")
            }
        }
    }
}

// MARK: - Progress Indicator
struct ProgressIndicator: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.orange : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Profile Data Model
struct ProfileData {
    var name: String = ""
    var age: Int = 25
    var gender: Gender = .preferNotToSay
    var skinType: Int = 3

    var calculatedMED: Int {
        UVCalculations.calculateMED(skinType: skinType, age: age, gender: gender)
    }
}