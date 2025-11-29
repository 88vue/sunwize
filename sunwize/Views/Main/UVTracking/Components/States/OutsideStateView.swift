import SwiftUI

/// Outside state view with progress ring
struct OutsideStateView: View {
    // MARK: - Properties
    let sessionSED: Double
    let exposureRatio: Double
    let sessionStartTime: Date?
    let med: Int

    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(spacing: 20) {
                // Icon
                StateIconCircle.outside

                // Title
                Text("You are outside")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 8)

                // Progress Ring
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.progressRingBackground, lineWidth: Layout.UV.progressRingLineWidth)
                        .frame(width: Spacing.UV.progressRingSize, height: Spacing.UV.progressRingSize)

                    // Progress ring with gradient
                    Circle()
                        .trim(from: 0, to: min(exposureRatio, 1.0))
                        .stroke(
                            Color.progressColor(for: exposureRatio),
                            style: StrokeStyle(lineWidth: Layout.UV.progressRingLineWidth, lineCap: .round)
                        )
                        .frame(width: Spacing.UV.progressRingSize, height: Spacing.UV.progressRingSize)
                        .rotationEffect(.degrees(-90))
                        .animation(.progressUpdate, value: exposureRatio)

                    // Percentage text
                    VStack(spacing: 4) {
                        Text("\(Int(exposureRatio * 100))%")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text("Session Exposure")
                            .font(.system(size: 16))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 16)

                // Divider
                Divider()
                    .padding(.horizontal, 32)

                // Start time
                if let startTime = sessionStartTime {
                    Text("Started \(startTime.formattedTime())")
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview
#Preview("Outside State") {
    VStack(spacing: 20) {
        OutsideStateView(
            sessionSED: 50,
            exposureRatio: 0.25,
            sessionStartTime: Date().addingTimeInterval(-1800),
            med: 300
        )

        OutsideStateView(
            sessionSED: 150,
            exposureRatio: 0.65,
            sessionStartTime: Date().addingTimeInterval(-3600),
            med: 300
        )

        OutsideStateView(
            sessionSED: 280,
            exposureRatio: 0.93,
            sessionStartTime: Date().addingTimeInterval(-5400),
            med: 300
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
