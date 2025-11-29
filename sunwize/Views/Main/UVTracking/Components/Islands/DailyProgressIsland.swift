import SwiftUI

/// Daily progress island with current IU, target, and streak badge
struct DailyProgressIsland: View {
    // MARK: - Properties
    let current: Double
    let target: Double
    let streak: Int
    let onStreakTap: () -> Void

    // MARK: - Body
    var body: some View {
        IslandCard(padding: 16) {
            HStack(spacing: 0) {
                // Left side: Progress text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Progress")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(formatNumber(current))")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text("/ \(formatNumber(target)) IU")
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                // Right side: Streak badge
                Button(action: onStreakTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "414141")!)

                        Text("\(streak) Day Streak")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "414141")!)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.vitaminDPrimary)
                    .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Helpers
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Preview
#Preview("Daily Progress Island") {
    VStack(spacing: 20) {
        DailyProgressIsland(
            current: 1400,
            target: 2000,
            streak: 12,
            onStreakTap: {
                print("Streak tapped")
            }
        )

        DailyProgressIsland(
            current: 500,
            target: 2000,
            streak: 3,
            onStreakTap: {
                print("Streak tapped")
            }
        )

        DailyProgressIsland(
            current: 2200,
            target: 2000,
            streak: 25,
            onStreakTap: {
                print("Streak tapped")
            }
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
