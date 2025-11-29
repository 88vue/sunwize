import SwiftUI

/// Inside state view component
struct InsideStateView: View {
    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(spacing: 20) {
                // Icon
                StateIconCircle.inside

                // Title
                Text("You are inside")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 8)

                // Description
                Text("UV exposure tracking paused while Indoors")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "040404")!)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: Layout.UV.stateContainerHeight)
    }
}

// MARK: - Preview
#Preview("Inside State") {
    InsideStateView()
        .padding()
        .background(Color(.systemGroupedBackground))
}
