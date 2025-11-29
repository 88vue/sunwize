import SwiftUI

/// Action buttons island (sunscreen and under cover)
struct ActionIsland: View {
    // MARK: - Properties
    let showSunscreen: Bool
    let showUnderCover: Bool
    let onApplySunscreen: () -> Void
    let onUnderCover: () -> Void

    // MARK: - Body
    var body: some View {
        IslandCard {
            HStack(spacing: 12) {
                if showSunscreen {
                    PrimaryButton(
                        title: "Apply\nSunscreen",
                        icon: "sun.max",
                        style: .primary,
                        action: onApplySunscreen
                    )
                }

                if showUnderCover {
                    PrimaryButton(
                        title: "I'm under cover!",
                        icon: "umbrella.fill",
                        style: .secondary,
                        action: onUnderCover
                    )
                }
            }
        }

    }
}

// MARK: - Preview
#Preview("Action Island") {
    VStack(spacing: 20) {
        ActionIsland(
            showSunscreen: true,
            showUnderCover: true,
            onApplySunscreen: { print("Apply sunscreen") },
            onUnderCover: { print("Under cover") }
        )

        ActionIsland(
            showSunscreen: true,
            showUnderCover: false,
            onApplySunscreen: { print("Apply sunscreen") },
            onUnderCover: { print("Under cover") }
        )

        ActionIsland(
            showSunscreen: false,
            showUnderCover: true,
            onApplySunscreen: { print("Apply sunscreen") },
            onUnderCover: { print("Under cover") }
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
