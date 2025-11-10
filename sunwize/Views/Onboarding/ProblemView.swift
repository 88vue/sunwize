import SwiftUI

struct ProblemView: View {
    let onContinue: () -> Void
    let onBack: () -> Void
    @State private var animateStats = false

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("The Problem")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Skin cancer in Australia")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // Statistics
            VStack(spacing: 24) {
                StatCard(
                    number: "2 out of 3",
                    description: "Australians will be diagnosed with skin cancer in their lifetime",
                    color: .red,
                    animate: animateStats
                )

                StatCard(
                    number: "$1.8 Billion",
                    description: "Annual cost of skin cancer to the Australian healthcare system",
                    color: .orange,
                    animate: animateStats
                )

                StatCard(
                    number: "100%",
                    description: "Of skin cancers are preventable with proper sun safety",
                    color: .green,
                    animate: animateStats
                )
            }
            .padding(.horizontal, 20)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                    animateStats = true
                }
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
                        Text("Learn how Sunwize helps")
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

struct StatCard: View {
    let number: String
    let description: String
    let color: Color
    let animate: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(number)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: color.opacity(0.2), radius: 8, y: 4)
        )
        .scaleEffect(animate ? 1.0 : 0.9)
        .opacity(animate ? 1.0 : 0.0)
    }
}