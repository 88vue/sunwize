import SwiftUI

/// Profile information row with label, value, and optional detail
/// Updated design with chevron indicator matching Figma
struct ProfileInfoRow: View {
    let label: String
    let value: String
    var detail: String? = nil
    var showChevron: Bool = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(label)
                    .font(.system(size: Typography.caption))
                    .foregroundColor(.slate500)

                Text(value)
                    .font(.system(size: Typography.body, weight: .semibold))
                    .foregroundColor(.textPrimary)

                if let detail = detail {
                    Text(detail)
                        .font(.system(size: Typography.caption2))
                        .foregroundColor(.slate400)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: Typography.footnote, weight: .medium))
                    .foregroundColor(.slate400)
            }
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.base)
    }
}

// MARK: - Preview
#Preview("Profile Info Row") {
    VStack(spacing: 0) {
        ProfileInfoRow(
            label: "Skin Type",
            value: "Type III",
            detail: "Burns moderately, tans gradually",
            showChevron: true
        )

        Divider().padding(.leading, Spacing.base)

        ProfileInfoRow(
            label: "Age",
            value: "30 years",
            showChevron: true
        )

        Divider().padding(.leading, Spacing.base)

        ProfileInfoRow(
            label: "MED Value",
            value: "300 J/m²",
            detail: "Personalized minimal erythemal dose"
        )
    }
    .background(Color(.systemBackground))
    .cornerRadius(CornerRadius.base)
    .padding()
    .background(Color(.systemGroupedBackground))
}
