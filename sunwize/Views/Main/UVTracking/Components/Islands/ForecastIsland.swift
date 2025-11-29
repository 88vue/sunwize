import SwiftUI

/// Mini UV forecast island component
struct ForecastIsland: View {
    // MARK: - Properties
    let uvForecast: [UVForecastData]
    let onViewFullForecast: () -> Void

    // Next 12 hours of forecast
    private var next12Hours: [UVForecastData] {
        let now = Date()
        let twelveHoursLater = now.addingTimeInterval(12 * 3600)
        return uvForecast.filter { $0.time >= now && $0.time <= twelveHoursLater }
    }

    // MARK: - Body
    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("UV Forecast")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Button(action: onViewFullForecast) {
                        HStack(spacing: 4) {
                            Text("View Full Forecast")
                                .font(.system(size: 12, weight: .medium))
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Mini chart with time labels
                if !next12Hours.isEmpty {
                    VStack(spacing: 4) {
                        MiniUVChart(data: next12Hours)
                            .frame(height: Spacing.UV.miniGraphHeight - 20)

                        // Time labels
                        GeometryReader { geo in
                            let width = geo.size.width
                            let count = next12Hours.count
                            let step = count > 1 ? width / CGFloat(count - 1) : 0
                            
                            ForEach(Array(next12Hours.enumerated()), id: \.element.time) { index, item in
                                Text(formatTime(item.time))
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)
                                    .position(x: CGFloat(index) * step, y: geo.size.height / 2)
                            }
                        }
                        .frame(height: 15)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Spacing.UV.miniGraphHeight)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.base)
                            .fill(Color(.systemGroupedBackground))
                            .frame(height: Spacing.UV.miniGraphHeight)

                        Text("Loading forecast...")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }

    }

    // MARK: - Helper Methods
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date).lowercased().replacingOccurrences(of: " ", with: "")
    }
}

// MARK: - Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Simple mini UV chart component
struct MiniUVChart: View {
    let data: [UVForecastData]

    private var maxUV: Double {
        data.map { $0.uvIndex }.max() ?? 10
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Gradient area fill
                Path { path in
                    guard !data.isEmpty else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height
                    let stepX = width / CGFloat(max(data.count - 1, 1))

                    // Start at bottom left
                    path.move(to: CGPoint(x: 0, y: height))

                    // Draw line through data points
                    for (index, point) in data.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(point.uvIndex / maxUV) * height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    // Close path at bottom right
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.3),
                            Color.orange.opacity(0.05)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line path
                Path { path in
                    guard !data.isEmpty else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height
                    let stepX = width / CGFloat(max(data.count - 1, 1))

                    // Start at first point
                    let firstY = height - (CGFloat(data[0].uvIndex / maxUV) * height)
                    path.move(to: CGPoint(x: 0, y: firstY))

                    // Draw line through data points
                    for (index, point) in data.enumerated().dropFirst() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(point.uvIndex / maxUV) * height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.orange, lineWidth: 2)
            }
        }
    }
}

// MARK: - Preview
#Preview("Forecast Island") {
    VStack(spacing: 20) {
        ForecastIsland(
            uvForecast: PreviewData.sampleUVForecast
        ) {
            print("View full forecast")
        }

        ForecastIsland(uvForecast: []) {
            print("View full forecast")
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

// MARK: - Preview Data
enum PreviewData {
    static var sampleUVForecast: [UVForecastData] {
        let now = Date()
        return (0..<24).map { hour in
            let time = now.addingTimeInterval(Double(hour) * 3600)
            // Simulate UV curve peaking at noon
            let hourOfDay = Calendar.current.component(.hour, from: time)
            let uvIndex = max(0, 8 * sin(Double(hourOfDay - 6) * .pi / 12))
            return UVForecastData(time: time, uvIndex: uvIndex)
        }
    }
}
