import SwiftUI

/// Island component displaying current UV index and streak
struct UVIndexIsland: View {
    // MARK: - Properties
    let uvIndex: Double
    let streak: Int
    let onStreakTap: () -> Void

    // MARK: - Body
    var body: some View {
        IslandCard(padding: 16) {
            HStack(spacing: 0) {
                // UV Index Section
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current UV Index")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(uvIndex))")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text(Color.uvIndexClassification(for: uvIndex))
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                // Streak Button
                Button(action: onStreakTap) {
                    HStack(spacing: 6) {
                        Image(systemName: UVStateIcon.streak)
                            .font(.system(size: 14))
                            .foregroundColor(.white)

                        Text("\(streak) Day Streak")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.uvStreakBackground)
                    .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }

    }
}

// MARK: - Preview
#Preview("UV Index Island") {
    VStack(spacing: 20) {
        UVIndexIsland(uvIndex: 2, streak: 5) {
            print("Streak tapped")
        }

        UVIndexIsland(uvIndex: 5, streak: 12) {
            print("Streak tapped")
        }

        UVIndexIsland(uvIndex: 7, streak: 3) {
            print("Streak tapped")
        }

        UVIndexIsland(uvIndex: 9, streak: 21) {
            print("Streak tapped")
        }

        UVIndexIsland(uvIndex: 11, streak: 0) {
            print("Streak tapped")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
