import SwiftUI

/// Island with body exposure slider
struct BodyExposureIsland: View {
    // MARK: - Properties
    @Binding var exposureFactor: Double
    let onChange: (Double) -> Void

    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text("Body Exposure")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)

                // Slider
                VStack(spacing: 24) {
                    CustomSlider(
                        value: $exposureFactor,
                        range: 0...1,
                        trackColor: Color.vitaminDSliderBlue,
                        backgroundColor: Color.neutral200.opacity(0.6),
                        thumbSize: Layout.VitaminD.sliderThumbSize,
                        trackHeight: Layout.VitaminD.sliderHeight
                    ) { newValue in
                        onChange(newValue)
                    }

                    // Percentage display
                    VStack(spacing: 4) {
                        Text("\(Int(exposureFactor * 100))%")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)

                        Text("Skin area exposed to sun")
                            .font(.system(size: 12))
                            .foregroundColor(.slate500)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: Layout.VitaminD.bodyExposureIslandHeight)
    }
}

// MARK: - Custom Slider
struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let trackColor: Color
    let backgroundColor: Color
    let thumbSize: CGFloat
    let trackHeight: CGFloat
    let onChange: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let thumbPosition = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * (geometry.size.width - thumbSize)

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(backgroundColor)
                    .frame(height: trackHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: trackHeight / 2)
                            .stroke(Color(hex: "B7B5B5")!, lineWidth: 0.5)
                    )

                // Progress track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(trackColor)
                    .frame(width: thumbPosition + thumbSize / 2, height: trackHeight)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .offset(x: thumbPosition)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                isDragging = true
                                updateValue(from: gesture.location.x, in: geometry.size.width)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .onTapGesture { location in
                updateValue(from: location.x, in: geometry.size.width)
            }
        }
        .frame(height: thumbSize)
    }

    private func updateValue(from position: CGFloat, in width: CGFloat) {
        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(max(0, min(position, width)) / width)
        value = newValue
        onChange(newValue)
    }
}

// MARK: - Neutral Color Extension
extension Color {
    static let neutral200 = Color(hex: "E5E5EA")!
}

// MARK: - Preview
#Preview("Body Exposure Island") {
    struct PreviewWrapper: View {
        @State private var exposure: Double = 0.4

        var body: some View {
            VStack(spacing: 20) {
                BodyExposureIsland(
                    exposureFactor: $exposure,
                    onChange: { newValue in
                        print("Exposure changed to: \(Int(newValue * 100))%")
                    }
                )

                Text("Current: \(Int(exposure * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }

    return PreviewWrapper()
}
