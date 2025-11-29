import SwiftUI

/// Unknown/calculating state view component
struct UnknownStateView: View {
    // MARK: - Properties
    let reason: String?
    let onRetry: (() -> Void)?

    init(reason: String? = nil, onRetry: (() -> Void)? = nil) {
        self.reason = reason
        self.onRetry = onRetry
    }

    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(spacing: 20) {
                // Icon with background
                StateIconCircle.unknown

                // Title
                Text("Calculating...")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 16)

                // Description
                Text(reason ?? "We will update your state as soon as we're certain")
                    .font(.system(size: 20))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Retry button (optional)
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.actionPrimary)
                            .cornerRadius(20)
                    }
                    .padding(.top, 8)
                }

                Spacer()
                    .frame(height: 32)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: Layout.UV.stateContainerHeight)
    }
}

// MARK: - Preview
#Preview("Unknown State") {
    VStack(spacing: 20) {
        UnknownStateView()

        UnknownStateView(reason: "Waiting for better GPS signal") {
            print("Retry tapped")
        }

        UnknownStateView(reason: "Location services unavailable") {
            print("Retry tapped")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
