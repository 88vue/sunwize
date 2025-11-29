import SwiftUI

/// Vehicle state view component
struct VehicleStateView: View {
    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(spacing: 20) {
                // Icon
                StateIconCircle.vehicle

                // Title
                Text("You are driving")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 8)

                // Description
                Text("UV exposure tracking paused while driving")
                    .font(.system(size: 20))
                    .foregroundColor(.textPrimary)
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
#Preview("Vehicle State") {
    VehicleStateView()
        .padding()
        .background(Color(.systemGroupedBackground))
}
