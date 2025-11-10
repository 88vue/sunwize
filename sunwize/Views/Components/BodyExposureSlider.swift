import SwiftUI

struct BodyExposureSlider: View {
    @Binding var value: Double
    let onChange: (Double) -> Void

    private let exposureLevels = [
        (value: 0.1, label: "Face & Hands", icon: "face.smiling"),
        (value: 0.3, label: "T-shirt & Shorts", icon: "tshirt"),
        (value: 0.5, label: "Tank Top & Shorts", icon: "figure.walk"),
        (value: 0.8, label: "Swimwear", icon: "figure.pool.swim")
    ]

    private var currentLevel: (value: Double, label: String, icon: String) {
        let closest = exposureLevels.min { abs($0.value - value) < abs($1.value - value) }
        return closest ?? exposureLevels[1]
    }

    var body: some View {
        VStack(spacing: 16) {
            // Title
            HStack {
                Label("Body Exposure", systemImage: "figure.stand")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            // Current level display
            HStack(spacing: 12) {
                Image(systemName: currentLevel.icon)
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentLevel.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("\(Int(value * 100))% skin exposed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
            )

            // Slider (left = no clothes, right = fully clothed)
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "figure.pool.swim")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(
                        value: Binding(
                            get: { value },
                            set: {
                                value = $0
                                onChange(value)
                            }
                        ),
                        in: 0.1...0.8,
                        step: 0.1
                    )
                    .accentColor(.orange)

                    Image(systemName: "figure.stand")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Level indicators
                HStack {
                    ForEach(exposureLevels, id: \.value) { level in
                        VStack {
                            Circle()
                                .fill(abs(value - level.value) < 0.05 ? Color.orange : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)

                            Text(level.label)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                        }

                        if level.value != exposureLevels.last?.value {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            // Info text
            Text("Adjust based on your clothing to get accurate Vitamin D calculations")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.05))
        )
    }
}