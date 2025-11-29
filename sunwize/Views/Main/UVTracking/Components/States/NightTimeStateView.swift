import SwiftUI

/// Night time state view component
struct NightTimeStateView: View {
    // MARK: - Properties
    let sunsetTime: Date?
    let sunriseTime: Date?

    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(spacing: 20) {
                // Icon
                StateIconCircle.nightTime

                // Title
                Text("It's night time")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 16)

                // Description
                if let sunriseTime = sunriseTime {
                    Text("See you tomorrow at \(sunriseTime.formattedTime())!")
                        .font(.system(size: 20))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                } else {
                    Text("See you tomorrow!")
                        .font(.system(size: 20))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: Layout.UV.stateContainerHeight)
    }
}

// MARK: - Preview
#Preview("Night Time State") {
    VStack(spacing: 20) {
        NightTimeStateView(
            sunsetTime: Date(),
            sunriseTime: Calendar.current.date(byAdding: .hour, value: 8, to: Date())
        )

        NightTimeStateView(sunsetTime: nil, sunriseTime: nil)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
