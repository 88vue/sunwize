import SwiftUI

struct SolutionView: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    @State private var animateFeatures = false

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("The Solution")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("How Sunwize helps")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // Features
            VStack(spacing: 20) {
                SolutionCard(
                    icon: "sun.max.fill",
                    title: "Track UV & Vitamin D",
                    description: "Real-time monitoring of your sun exposure with personalized safe limits based on your skin type",
                    color: .orange,
                    delay: 0.1,
                    animate: animateFeatures
                )

                SolutionCard(
                    icon: "shield.checkered",
                    title: "Get the Right Vitamin D Safely",
                    description: "Balance sun exposure to get healthy Vitamin D without risking sunburn",
                    color: .yellow,
                    delay: 0.2,
                    animate: animateFeatures
                )

                SolutionCard(
                    icon: "camera.viewfinder",
                    title: "Monitor Body Spots",
                    description: "Track skin changes over time with 3D body mapping for early detection",
                    color: .blue,
                    delay: 0.3,
                    animate: animateFeatures
                )
            }
            .padding(.horizontal, 20)
            .onAppear {
                animateFeatures = true
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .frame(width: 50, height: 50)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                }

                Button(action: onContinue) {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct SolutionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let delay: Double
    let animate: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .scaleEffect(animate ? 1.0 : 0.9)
        .opacity(animate ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.5).delay(delay), value: animate)
    }
}