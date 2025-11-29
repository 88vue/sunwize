import SwiftUI

/// Statistics card component for profile view
/// Centered design with icon circle, value and title matching Figma
struct StatsCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Icon in colored circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: Typography.title3, weight: .semibold))
                    .foregroundColor(color)
            }

            // Value
            Text(value)
                .font(.system(size: Typography.title3, weight: .bold))
                .foregroundColor(.textPrimary)

            // Title
            Text(title)
                .font(.system(size: Typography.caption))
                .foregroundColor(.slate500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.md)
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.base)
    }
}

// MARK: - Preview
#Preview("Stats Card") {
    HStack(spacing: Spacing.base) {
        StatsCard(
            icon: "shield.fill",
            title: "UV Safe Streak",
            value: "7 days",
            color: .green
        )

        StatsCard(
            icon: "sparkles",
            title: "Vitamin D Streak",
            value: "14 days",
            color: .orange
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
