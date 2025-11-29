import SwiftUI

/// Grid selector for Fitzpatrick skin types
/// Shows a 3x2 grid with skin tone circles and type labels
struct SkinTypeGridSelector: View {
    // MARK: - Properties
    @Binding var selectedType: Int
    var label: String = "Skin Type"

    // Skin tone colors for each Fitzpatrick type
    private let skinColors: [Color] = [
        Color(hex: "FFE4C9")!, // Type I - Very fair
        Color(hex: "F5D0B0")!, // Type II - Fair
        Color(hex: "D4A574")!, // Type III - Medium
        Color(hex: "B07D4E")!, // Type IV - Olive
        Color(hex: "7B4D2E")!, // Type V - Brown
        Color(hex: "4A2C17")!  // Type VI - Dark brown
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(label)
                .font(.system(size: Typography.subheadline, weight: .medium))
                .foregroundColor(.slate700)

            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(1...6, id: \.self) { type in
                    SkinTypeOption(
                        type: type,
                        color: skinColors[type - 1],
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                    }
                }
            }
        }
    }
}

// MARK: - Skin Type Option
private struct SkinTypeOption: View {
    let type: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                // Skin tone circle
                Circle()
                    .fill(color)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 3)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )

                // Type label
                Text("Type \(type)")
                    .font(.system(size: Typography.footnote, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .orange : .slate600)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(isSelected ? Color.orange.opacity(0.08) : Color(.systemGray6))
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview("Skin Type Grid Selector") {
    VStack(spacing: Spacing.xl) {
        SkinTypeGridSelector(
            selectedType: .constant(3),
            label: "Select Your Skin Type"
        )

        // Show selected type description
        if let skinType = FitzpatrickSkinType(rawValue: 3) {
            Text(skinType.description)
                .font(.system(size: Typography.subheadline))
                .foregroundColor(.slate600)
                .multilineTextAlignment(.center)
        }
    }
    .padding()
    .background(Color(.systemBackground))
}
