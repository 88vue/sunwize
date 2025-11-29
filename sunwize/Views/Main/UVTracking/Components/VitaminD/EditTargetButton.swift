import SwiftUI

/// Standalone gold button for editing vitamin D target
struct EditTargetButton: View {
    // MARK: - Properties
    let action: () -> Void

    // MARK: - Body
    var body: some View {
        Button(action: action) {
            Text("Edit Target")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vitaminDText)
                .frame(width: Layout.VitaminD.editTargetButtonWidth, height: Layout.VitaminD.editTargetButtonHeight)
                .background(Color.vitaminDPrimary)
                .cornerRadius(CornerRadius.base)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview("Edit Target Button") {
    VStack(spacing: 20) {
        EditTargetButton {
            print("Edit target tapped")
        }

        // Different states
        EditTargetButton {
            print("Edit target tapped")
        }
        .opacity(0.6)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
