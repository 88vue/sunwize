import SwiftUI

/// Sunsafe state view component (sunscreen active)
struct SunSafeStateView: View {
    // MARK: - Properties
    let spf: Int
    let appliedTime: Date
    let reapplyTime: Date
    let onReapply: () -> Void

    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(spacing: 20) {
                // Icon
                StateIconCircle.sunSafe

                // Title
                Text("You are sunsafe")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)

                // SPF info
                Text("SPF \(spf) protection active")
                    .font(.system(size: 16))
                    .foregroundColor(Color.black.opacity(0.8))
                    .padding(.bottom, 8)

                // Time details card
                VStack(spacing: 0) {
                    // Applied at
                    HStack {
                        Text("Applied at")
                            .font(.system(size: 16))
                            .foregroundColor(Color.black.opacity(0.8))

                        Spacer()

                        Text(appliedTime.formattedTime())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Reapply by
                    HStack {
                        Text("Reapply by")
                            .font(.system(size: 16))
                            .foregroundColor(Color.black.opacity(0.8))

                        Spacer()

                        Text(reapplyTime.formattedTime())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(Color(hex: "CACACA")!.opacity(0.2))
                .cornerRadius(CornerRadius.base)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Preview
#Preview("SunSafe State") {
    VStack(spacing: 20) {
        SunSafeStateView(
            spf: 50,
            appliedTime: Date().addingTimeInterval(-1800),
            reapplyTime: Date().addingTimeInterval(5400)
        ) {
            print("Reapply tapped")
        }

        SunSafeStateView(
            spf: 30,
            appliedTime: Date().addingTimeInterval(-3600),
            reapplyTime: Date().addingTimeInterval(3600)
        ) {
            print("Reapply tapped")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
