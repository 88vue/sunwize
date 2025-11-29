import SwiftUI

/// Bottom sheet popup for editing user profile
/// Follows the same pattern as EditTargetPopup for consistency
struct EditProfilePopup: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let profile: Profile
    let onSave: (Profile) -> Void

    // Local state for editing
    @State private var name: String
    @State private var age: Int
    @State private var gender: Gender
    @State private var skinType: Int

    // MARK: - Initialization
    init(isPresented: Binding<Bool>, profile: Profile, onSave: @escaping (Profile) -> Void) {
        self._isPresented = isPresented
        self.profile = profile
        self.onSave = onSave

        // Initialize local state from profile
        self._name = State(initialValue: profile.name)
        self._age = State(initialValue: profile.age)
        self._gender = State(initialValue: profile.gender)
        self._skinType = State(initialValue: profile.skinType)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            BottomSheetHeader(title: "Edit Profile", isPresented: $isPresented)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Personal Info Section
                    VStack(alignment: .leading, spacing: Spacing.base) {
                        SectionHeader(icon: "person.fill", title: "Personal Info")

                        VStack(spacing: Spacing.base) {
                            FormTextField(
                                label: "Name",
                                text: $name,
                                placeholder: "Enter your name"
                            )

                            FormNumberField(
                                label: "Age",
                                value: $age,
                                placeholder: "Enter age",
                                suffix: "years"
                            )

                            // Gender Picker
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Gender")
                                    .font(.system(size: Typography.subheadline, weight: .medium))
                                    .foregroundColor(.slate700)

                                Menu {
                                    ForEach(Gender.allCases, id: \.self) { genderOption in
                                        Button(action: {
                                            gender = genderOption
                                        }) {
                                            HStack {
                                                Text(genderOption.displayName)
                                                if gender == genderOption {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(gender.displayName)
                                            .font(.system(size: Typography.body))
                                            .foregroundColor(.textPrimary)

                                        Spacer()

                                        Image(systemName: "chevron.down")
                                            .font(.system(size: Typography.footnote, weight: .medium))
                                            .foregroundColor(.slate500)
                                    }
                                    .padding(.horizontal, Spacing.base)
                                    .frame(height: 52)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(CornerRadius.sm)
                                }
                            }
                        }
                    }

                    // Skin Profile Section
                    VStack(alignment: .leading, spacing: Spacing.base) {
                        SectionHeader(icon: "sun.max.fill", title: "Skin Profile")

                        SkinTypeGridSelector(
                            selectedType: $skinType,
                            label: "Select Your Skin Type"
                        )

                        // Skin type description
                        if let fitzpatrickType = FitzpatrickSkinType(rawValue: skinType) {
                            HStack(alignment: .top, spacing: Spacing.md) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: Typography.body))
                                    .foregroundColor(.blue)

                                Text(fitzpatrickType.description)
                                    .font(.system(size: Typography.subheadline))
                                    .foregroundColor(.slate600)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(Spacing.base)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)
                        }
                    }

                    // Save Button
                    Button(action: saveProfile) {
                        Text("Save Changes")
                            .font(.system(size: Typography.body, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Layout.buttonHeight)
                            .background(Color.orange)
                            .cornerRadius(CornerRadius.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.5)
                    .padding(.top, Spacing.sm)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(.medium)
        .dragToDismiss($isPresented)
    }

    // MARK: - Computed Properties
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        age > 0 && age < 120 &&
        skinType >= 1 && skinType <= 6
    }

    // MARK: - Actions
    private func saveProfile() {
        let updatedMED = FitzpatrickSkinType(rawValue: skinType)?.baseMED ?? profile.med

        var updatedProfile = profile
        updatedProfile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedProfile.age = age
        updatedProfile.gender = gender
        updatedProfile.skinType = skinType
        updatedProfile.med = updatedMED
        updatedProfile.updatedAt = Date()

        onSave(updatedProfile)

        withAnimation {
            isPresented = false
        }
    }
}

// MARK: - Section Header
private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: Typography.body, weight: .semibold))
                .foregroundColor(.orange)

            Text(title)
                .font(.system(size: Typography.headline, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
    }
}

// MARK: - Preview
#Preview("Edit Profile Popup") {
    struct PreviewWrapper: View {
        @State private var isPresented = true
        @State private var profile = Profile(
            id: UUID(),
            email: "john@example.com",
            name: "John Doe",
            age: 30,
            gender: .male,
            skinType: 3,
            med: 400,
            onboardingCompleted: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack {
                    Text("Profile: \(profile.name)")
                        .font(.title)

                    Button("Show Edit Profile") {
                        isPresented = true
                    }
                }

                if isPresented {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isPresented = false
                        }

                    VStack {
                        Spacer()
                        EditProfilePopup(
                            isPresented: $isPresented,
                            profile: profile,
                            onSave: { updatedProfile in
                                profile = updatedProfile
                                print("Saved profile: \(updatedProfile.name)")
                            }
                        )
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
    }

    return PreviewWrapper()
}
