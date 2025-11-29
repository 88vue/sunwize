import SwiftUI

/// Feature toggle row with icon, title, description and toggle
/// Updated design with 40px colored icon circle matching Figma
struct FeatureToggleRow: View {
    let title: String
    let description: String
    let icon: String
    var iconColor: Color = .orange
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon in colored circle - 40px
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: Typography.headline, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.system(size: Typography.body, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(description)
                    .font(.system(size: Typography.caption))
                    .foregroundColor(.slate500)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.orange)
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.base)
    }
}

// MARK: - Preview
#Preview("Feature Toggle Row") {
    VStack(spacing: 0) {
        FeatureToggleRow(
            title: "UV Tracking",
            description: "Monitor UV exposure when outside",
            icon: "sun.max.fill",
            iconColor: .orange,
            isOn: .constant(true)
        )

        Divider().padding(.leading, 72)

        FeatureToggleRow(
            title: "Vitamin D Tracking",
            description: "Calculate Vitamin D synthesis",
            icon: "sparkles",
            iconColor: .yellow,
            isOn: .constant(true)
        )

        Divider().padding(.leading, 72)

        FeatureToggleRow(
            title: "Body Spot Reminders",
            description: "Monthly reminders for body spots",
            icon: "bell.fill",
            iconColor: .blue,
            isOn: .constant(false)
        )
    }
    .background(Color(.systemBackground))
    .cornerRadius(CornerRadius.base)
    .padding()
    .background(Color(.systemGroupedBackground))
}
