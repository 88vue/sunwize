import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @State private var showingEditProfile = false
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    ProfileHeaderView(profile: profileViewModel.profile)
                        .padding(.top)

                    // Stats Cards
                    HStack(spacing: 16) {
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
                            color: .yellow
                        )
                    }
                    .padding(.horizontal)

                    // Skin Profile Section
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Skin Profile", systemImage: "sun.max.fill")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 12) {
                            ProfileInfoRow(
                                label: "Skin Type",
                                value: "Type \(profileViewModel.profile.skinType)",
                                detail: FitzpatrickSkinType(rawValue: profileViewModel.profile.skinType)?.description
                            )

                            ProfileInfoRow(
                                label: "Age",
                                value: "\(profileViewModel.profile.age) years"
                            )

                            ProfileInfoRow(
                                label: "MED Value",
                                value: "\(profileViewModel.profile.med) J/m²",
                                detail: "Personalized minimal erythemal dose"
                            )
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // Feature Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Feature Settings", systemImage: "gearshape.fill")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            FeatureToggleRow(
                                title: "UV Tracking",
                                description: "Monitor UV exposure when outside",
                                icon: "sun.max.fill",
                                isOn: Binding(
                                    get: { profileViewModel.featureSettings?.uvTrackingEnabled ?? true },
                                    set: { newValue in
                                        updateFeatureSetting { settings in
                                            settings.uvTrackingEnabled = newValue
                                        }
                                    }
                                )
                            )

                            Divider().padding(.leading, 48)

                            FeatureToggleRow(
                                title: "Vitamin D Tracking",
                                description: "Calculate Vitamin D synthesis",
                                icon: "sparkles",
                                isOn: Binding(
                                    get: { profileViewModel.featureSettings?.vitaminDTrackingEnabled ?? true },
                                    set: { newValue in
                                        updateFeatureSetting { settings in
                                            settings.vitaminDTrackingEnabled = newValue
                                        }
                                    }
                                )
                            )

                            Divider().padding(.leading, 48)

                            FeatureToggleRow(
                                title: "Body Scan Reminders",
                                description: "Monthly reminders for body scans",
                                icon: "bell.fill",
                                isOn: Binding(
                                    get: { profileViewModel.featureSettings?.bodyScanRemindersEnabled ?? true },
                                    set: { newValue in
                                        updateFeatureSetting { settings in
                                            settings.bodyScanRemindersEnabled = newValue
                                        }
                                        Task {
                                            if newValue {
                                                await NotificationManager.shared.scheduleMonthlyBodyScanReminder()
                                            } else {
                                                await NotificationManager.shared.cancelBodyScanReminders()
                                            }
                                        }
                                    }
                                )
                            )
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button(action: { showingEditProfile = true }) {
                            HStack {
                                Image(systemName: "person.text.rectangle")
                                Text("Edit Profile")
                            }
                            .font(.headline)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }

                        Button(action: { showingSignOutConfirmation = true }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Footer
                    VStack(spacing: 8) {
                        Text("Sunwize v1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Made with ☀️ for your skin health")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(profile: profileViewModel.profile) { updatedProfile in
                Task {
                    try? await authService.updateProfile(updatedProfile)
                    profileViewModel.profile = updatedProfile
                }
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

// MARK: - Profile Header
struct ProfileHeaderView: View {
    let profile: Profile

    var body: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange, Color.yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)

                Text(profile.name.prefix(2).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text(profile.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(profile.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Member since \(profile.createdAt, format: .dateTime.month().year())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Stats Card
struct StatsCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Profile Info Row
struct ProfileInfoRow: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let detail = detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Feature Toggle Row
struct FeatureToggleRow: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.orange)
        }
        .padding()
    }
}
