import SwiftUI

/// Profile header with avatar and user info
/// Styled as a white card with centered content matching Figma design
struct ProfileHeaderView: View {
    let profile: Profile

    var body: some View {
        VStack(spacing: Spacing.base) {
            // Avatar - 96px with gradient
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange, Color(hex: "FFCC00")!],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)

                Text(initials)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }

            // User info
            VStack(spacing: Spacing.xs) {
                Text(profile.name)
                    .font(.system(size: Typography.title2, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(profile.email)
                    .font(.system(size: Typography.subheadline))
                    .foregroundColor(.slate500)

                Text("Member since \(profile.createdAt, format: .dateTime.month().year())")
                    .font(.system(size: Typography.caption))
                    .foregroundColor(.slate400)
            }
        }
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.base)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.base)
    }

    // MARK: - Computed Properties
    private var initials: String {
        let names = profile.name.split(separator: " ")
        if names.count >= 2 {
            return String(names[0].prefix(1) + names[1].prefix(1)).uppercased()
        } else {
            return String(profile.name.prefix(2)).uppercased()
        }
    }
}

// MARK: - Preview
#Preview("Profile Header") {
    ProfileHeaderView(profile: Profile(
        id: UUID(),
        email: "john@example.com",
        name: "John Doe",
        age: 30,
        gender: .male,
        skinType: 3,
        med: 300,
        onboardingCompleted: true,
        createdAt: Date(),
        updatedAt: Date()
    ))
    .padding()
    .background(Color(.systemGroupedBackground))
}
