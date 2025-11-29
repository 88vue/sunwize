import SwiftUI

/// Reusable bottom sheet header with drag handle and close button
/// Replaces duplicate header code across EditTargetPopup, UVForecastPopup, VitaminDHistoryPopup, etc.
struct BottomSheetHeader: View {
    // MARK: - Properties
    let title: String
    @Binding var isPresented: Bool
    var showCloseButton: Bool = true

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 9999)
                .fill(Color(.systemGray3))
                .frame(width: Layout.dragHandleWidth, height: Layout.dragHandleHeight)
                .padding(.top, Spacing.BottomSheet.dragHandleTop)
                .padding(.bottom, Spacing.BottomSheet.dragHandleBottom)

            // Header with title and close button
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: Typography.title3, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if showCloseButton {
                    Button(action: {
                        withAnimation {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: Typography.footnote, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: Layout.iconButtonSize, height: Layout.iconButtonSize)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.BottomSheet.headerBottom)
        }
    }
}

// MARK: - Preview
#Preview("Bottom Sheet Header") {
    VStack {
        Spacer()

        VStack(spacing: 0) {
            BottomSheetHeader(
                title: "Edit Daily Target",
                isPresented: .constant(true)
            )

            Text("Content goes here")
                .padding()

            Spacer()
        }
        .frame(height: 400)
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
    }
    .background(Color.black.opacity(0.3))
}
