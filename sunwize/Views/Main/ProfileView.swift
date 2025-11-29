import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @Binding var showingEditProfile: Bool
    @State private var showingSignOutConfirmation = false

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Page Header (like BodySpotView)
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Profile")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Manage your account")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                    // User Info Card
                    ProfileHeaderView(profile: profileViewModel.profile)
                        .padding(.horizontal, Spacing.base)

                        // Stats Cards
                        HStack(spacing: Spacing.base) {
                            StatsCard(
                                icon: "shield.fill",
                                title: "UV Safe Streak",
                                value: "\(profileViewModel.streaks?.uvSafeStreak ?? 0) days",
                                color: .green
                            )

                            StatsCard(
                                icon: "sparkles",
                                title: "Vitamin D Streak",
                                value: "\(profileViewModel.streaks?.vitaminDStreak ?? 0) days",
                                color: .orange
                            )
                        }
                        .padding(.horizontal, Spacing.base)

                        // Skin Profile Section
                        ProfileSection(icon: "sun.max.fill", title: "Skin Profile") {
                            VStack(spacing: 0) {
                                ProfileInfoRow(
                                    label: "Skin Type",
                                    value: "Type \(profileViewModel.profile.skinType)",
                                    detail: FitzpatrickSkinType(rawValue: profileViewModel.profile.skinType)?.description,
                                    showChevron: false
                                )

                                Divider().padding(.leading, Spacing.base)

                                ProfileInfoRow(
                                    label: "Age",
                                    value: "\(profileViewModel.profile.age) years",
                                    showChevron: false
                                )

                                Divider().padding(.leading, Spacing.base)

                                ProfileInfoRow(
                                    label: "MED Value",
                                    value: "\(profileViewModel.profile.med) J/m²",
                                    detail: "Personalized minimal erythemal dose",
                                    showChevron: false
                                )
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(CornerRadius.base)
                        }

                        // Feature Settings Section
                        ProfileSection(icon: "gearshape.fill", title: "Feature Settings") {
                            VStack(spacing: 0) {
                                FeatureToggleRow(
                                    title: "UV Tracking",
                                    description: "Monitor UV exposure when outside",
                                    icon: "sun.max.fill",
                                    iconColor: .orange,
                                    isOn: Binding(
                                        get: { profileViewModel.featureSettings?.uvTrackingEnabled ?? true },
                                        set: { newValue in
                                            updateFeatureSetting { settings in
                                                settings.uvTrackingEnabled = newValue
                                            }
                                        }
                                    )
                                )

                                Divider().padding(.leading, 72)

                                FeatureToggleRow(
                                    title: "Vitamin D Tracking",
                                    description: "Calculate Vitamin D synthesis",
                                    icon: "sparkles",
                                    iconColor: .yellow,
                                    isOn: Binding(
                                        get: { profileViewModel.featureSettings?.vitaminDTrackingEnabled ?? true },
                                        set: { newValue in
                                            updateFeatureSetting { settings in
                                                settings.vitaminDTrackingEnabled = newValue
                                            }
                                        }
                                    )
                                )

                                Divider().padding(.leading, 72)

                                FeatureToggleRow(
                                    title: "Body Spot Reminders",
                                    description: "Monthly reminders for body spots",
                                    icon: "bell.fill",
                                    iconColor: .blue,
                                    isOn: Binding(
                                        get: { profileViewModel.featureSettings?.bodyScanRemindersEnabled ?? true },
                                        set: { newValue in
                                            updateFeatureSetting { settings in
                                                settings.bodyScanRemindersEnabled = newValue
                                            }
                                            Task {
                                                if newValue {
                                                    await NotificationManager.shared.scheduleMonthlyBodySpotReminder()
                                                } else {
                                                    await NotificationManager.shared.cancelBodySpotReminders()
                                                }
                                            }
                                        }
                                    )
                                )
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(CornerRadius.base)
                        }

                        // Actions Section
                        VStack(spacing: Spacing.md) {
                            // Edit Profile Button
                            Button(action: {
                                withAnimation {
                                    showingEditProfile = true
                                }
                            }) {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: Typography.body, weight: .semibold))
                                    Text("Edit Profile")
                                        .font(.system(size: Typography.body, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: Layout.buttonHeight)
                                .background(Color.orange)
                                .cornerRadius(CornerRadius.sm)
                            }

                            // Sign Out Button
                            Button(action: { showingSignOutConfirmation = true }) {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: Typography.body, weight: .semibold))
                                    Text("Sign Out")
                                        .font(.system(size: Typography.body, weight: .semibold))
                                }
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: Layout.buttonHeight)
                                .background(Color(.systemBackground))
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.base)

                        // Footer
                        VStack(spacing: Spacing.xs) {
                            Text("Sunwize v1.0.0")
                                .font(.system(size: Typography.caption))
                                .foregroundColor(.slate400)

                            Text("Made with care for your skin health")
                                .font(.system(size: Typography.caption))
                                .foregroundColor(.slate400)
                        }
                        .padding(.vertical, Spacing.lg)
                    }
                    .padding(.bottom, Spacing.xl)
                }
        }
        .alert("Sign Out", isPresented: $showingSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authService.signOut()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private func updateFeatureSetting(_ update: (inout FeatureSettings) -> Void) {
        guard var settings = profileViewModel.featureSettings else { return }
        update(&settings)
        profileViewModel.featureSettings = settings

        Task {
            try? await SupabaseManager.shared.updateFeatureSettings(settings)
        }
    }
}

// MARK: - Profile Section Header
private struct ProfileSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header with SF Symbol icon
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: Typography.body, weight: .semibold))
                    .foregroundColor(.orange)

                Text(title)
                    .font(.system(size: Typography.headline, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            .padding(.horizontal, Spacing.base)

            content
        }
        .padding(.horizontal, Spacing.base)
    }
}

// NOTE: ProfileHeaderView, StatsCard, ProfileInfoRow, FeatureToggleRow, and EditProfilePopup
// are in Views/Components/Profile/
