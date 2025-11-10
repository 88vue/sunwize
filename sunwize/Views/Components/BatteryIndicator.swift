import SwiftUI

struct BatteryIndicator: View {
    let progress: Double
    let gradient: Bool
    var color: Color = .green

    private var fillColor: Color {
        if !gradient {
            return color
        }

        // Gradient colors based on exposure ratio
        switch progress {
        case 0..<0.25:
            return .green
        case 0.25..<0.5:
            return Color(red: 0.2, green: 0.7, blue: 0.9) // Light blue
        case 0.5..<0.75:
            return .yellow
        case 0.75..<1.0:
            return .orange
        default:
            return .red
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )

                // Battery fill
                if gradient && progress > 0 {
                    LinearGradient(
                        gradient: Gradient(stops: gradientStops()),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * min(progress, 1.0))
                    .cornerRadius(6)
                    .padding(2)
                } else if progress > 0 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fillColor)
                        .frame(width: geometry.size.width * min(progress, 1.0))
                        .padding(2)
                }

                // Battery cap
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray)
                        .frame(width: 6, height: geometry.size.height * 0.5)
                        .offset(x: 6)
                }

                // Percentage text
                if progress >= 0.3 {
                    Text("\(Int(min(progress, 1.0) * 100))%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                }
            }
        }
    }

    private func gradientStops() -> [Gradient.Stop] {
        let clampedProgress = min(progress, 1.0)
        var stops: [Gradient.Stop] = []

        if clampedProgress > 0 {
            stops.append(Gradient.Stop(color: .green, location: 0))
        }
        if clampedProgress > 0.25 {
            stops.append(Gradient.Stop(color: .green, location: 0.25 / clampedProgress))
            stops.append(Gradient.Stop(color: Color(red: 0.2, green: 0.7, blue: 0.9), location: 0.25 / clampedProgress))
        }
        if clampedProgress > 0.5 {
            stops.append(Gradient.Stop(color: .yellow, location: 0.5 / clampedProgress))
        }
        if clampedProgress > 0.75 {
            stops.append(Gradient.Stop(color: .orange, location: 0.75 / clampedProgress))
        }
        if clampedProgress >= 1.0 {
            stops.append(Gradient.Stop(color: .red, location: 1.0))
        }

        return stops
    }
}