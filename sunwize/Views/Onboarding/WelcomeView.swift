import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var sunScale: CGFloat = 0.8
    @State private var sunRotation: Double = 0

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated sun emoji
            Text("☀️")
                .font(.system(size: 120))
                .scaleEffect(sunScale)
                .rotationEffect(.degrees(sunRotation))
                .onAppear {
                    withAnimation(
                        Animation.easeInOut(duration: 2)
                            .repeatForever(autoreverses: true)
                    ) {
                        sunScale = 1.2
                    }
                    withAnimation(
                        Animation.linear(duration: 20)
                            .repeatForever(autoreverses: false)
                    ) {
                        sunRotation = 360
                    }
                }

            VStack(spacing: 16) {
                Text("Welcome to Sunwize")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Your personal guide to\nskin cancer prevention")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 20) {
                FeatureRow(
                    icon: "sun.max.fill",
                    title: "UV & Vitamin D Tracking",
                    description: "Monitor your sun exposure in real-time"
                )

                FeatureRow(
                    icon: "camera.fill",
                    title: "Body Scans",
                    description: "Track skin changes over time"
                )

                FeatureRow(
                    icon: "shield.fill",
                    title: "Personalized Protection",
                    description: "Get recommendations based on your skin type"
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            Button(action: onContinue) {
                HStack {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}