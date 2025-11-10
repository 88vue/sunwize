import SwiftUI

struct PersonalizedSetupView: View {
    let profileData: ProfileData
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var animateContent = false

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(animateContent ? 0 : -15))
                    .animation(.easeInOut(duration: 0.5), value: animateContent)

                Text("Nice to meet you, \(profileData.name)!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("We're setting up your Sunwize experience")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
            .onAppear {
                animateContent = true
            }

            // Personalized MED calculation
            VStack(spacing: 20) {
                Text("Your Personalized Settings")
                    .font(.headline)

                PersonalizedSettingCard(
                    title: "Skin Type",
                    value: "Type \(profileData.skinType)",
                    description: FitzpatrickSkinType(rawValue: profileData.skinType)?.description ?? "",
                    icon: "sun.max.fill",
                    color: .orange
                )

                PersonalizedSettingCard(
                    title: "MED Value",
                    value: "\(profileData.calculatedMED) J/m²",
                    description: "Your personalized Minimal Erythemal Dose",
                    icon: "shield.fill",
                    color: .blue
                )

                PersonalizedSettingCard(
                    title: "Daily Vitamin D Target",
                    value: "600 IU",
                    description: "Recommended daily intake",
                    icon: "sparkles",
                    color: .yellow
                )

                // Explanation
                Text("Your MED (Minimal Erythemal Dose) is calculated based on your skin type, age, and gender. This helps us provide personalized UV exposure recommendations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .opacity(animateContent ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.5).delay(0.3), value: animateContent)

            Spacer()

            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .frame(width: 50, height: 50)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                }

                Button(action: onContinue) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct PersonalizedSettingCard: View {
    let title: String
    let value: String
    let description: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}