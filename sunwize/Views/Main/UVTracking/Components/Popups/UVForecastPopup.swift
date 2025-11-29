import SwiftUI
#if canImport(Charts)
import Charts
#endif

/// Full UV forecast popup with daily breakdown
struct UVForecastPopup: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let uvForecast: [UVForecastData]

    @State private var selectedDay = 0

    // Split forecast into 24-hour chunks
    private var forecastDays: [[UVForecastData]] {
        let chunked = uvForecast.chunked(into: 24)
        return chunked
    }

    private var totalDays: Int {
        forecastDays.count
    }

    // Current day data
    private var currentDayData: [UVForecastData] {
        guard selectedDay < forecastDays.count else { return [] }
        return forecastDays[selectedDay]
    }

    // Peak UV for current day
    private var peakUV: UVForecastData? {
        currentDayData.max(by: { $0.uvIndex < $1.uvIndex })
    }

    // Peak hours range
    private var peakHoursRange: String {
        guard let peak = peakUV else { return "N/A" }

        // Find hours within 80% of peak
        let threshold = peak.uvIndex * 0.8
        let peakHours = currentDayData.filter { $0.uvIndex >= threshold }

        guard let first = peakHours.first, let last = peakHours.last else {
            return formatTime(peak.time)
        }

        return "\(formatTime(first.time)) - \(formatTime(last.time))"
    }

    // Title for the current day view
    private var currentDayTitle: String {
        guard selectedDay < forecastDays.count,
              let firstItem = forecastDays[selectedDay].first else {
            return "Forecast"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(firstItem.time) {
            return "Today Forecast"
        } else if calendar.isDateInTomorrow(firstItem.time) {
            return "Tomorrow Forecast"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return "\(formatter.string(from: firstItem.time)) Forecast"
        }
    }

    @State private var dragOffset: CGFloat = 0

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 9999)
                .fill(Color(.systemGray3))
                .frame(width: Layout.dragHandleWidth, height: Layout.dragHandleHeight)
                .padding(.top, Spacing.BottomSheet.dragHandleTop)
                .padding(.bottom, Spacing.BottomSheet.dragHandleBottom)

            // Header
            HStack(alignment: .top) {
                Text("UV Forecast")
                    .font(.system(size: Typography.title3, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: Typography.footnote, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: Layout.iconButtonSize, height: Layout.iconButtonSize)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.BottomSheet.headerBottom)
            
            VStack(spacing: 24) {
                // Day selector
                HStack(spacing: 12) {
                    Text(currentDayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(12)
                }

                // Day dots indicator
                if totalDays > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<min(totalDays, 5), id: \.self) { index in
                            Circle()
                                .fill(selectedDay == index ? Color.orange : Color.slate300)
                                .frame(width: 8, height: 8)
                                .onTapGesture {
                                    withAnimation {
                                        selectedDay = index
                                    }
                                }
                        }
                    }
                }

                // Swipeable Chart
                if !forecastDays.isEmpty {
                    TabView(selection: $selectedDay) {
                        ForEach(0..<forecastDays.count, id: \.self) { dayIndex in
                            if !forecastDays[dayIndex].isEmpty {
                                UVForecastChart(data: forecastDays[dayIndex])
                                    .frame(height: 290)
                                    .padding(.horizontal, 20)
                                    .tag(dayIndex)
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 290)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.base)
                            .fill(Color(.systemGroupedBackground))
                            .frame(height: 290)

                        Text("No forecast data available")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }

                // Peak hours info box
                if let peak = peakUV {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peak Hours")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)

                            Text(peakHoursRange)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Text("UV Index: \(Int(peak.uvIndex))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    .padding(16)
                    .background(Color.slate50)
                    .cornerRadius(CornerRadius.base)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, 110)
            
        }
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(.medium)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation {
                            isPresented = false
                        }
                    } else {
                        withAnimation {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Helper Methods
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - UV Forecast Chart Component
struct UVForecastChart: View {
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
                        let y = height - (CGFloat(point.uvIndex / maxUV) * height * 0.8) - (height * 0.1)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    // Close path at bottom right
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange.opacity(0.4),
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
                    let firstY = height - (CGFloat(data[0].uvIndex / maxUV) * height * 0.8) - (height * 0.1)
                    path.move(to: CGPoint(x: 0, y: firstY))

                    // Draw line through data points
                    for (index, point) in data.enumerated().dropFirst() {
                        let x = CGFloat(index) * stepX
                        let y = height - (CGFloat(point.uvIndex / maxUV) * height * 0.8) - (height * 0.1)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.orange, lineWidth: 3)

                // Time labels (every 4 hours)
                ForEach(Array(stride(from: 0, to: data.count, by: 4)), id: \.self) { index in
                    if index < data.count {
                        let x = (CGFloat(index) / CGFloat(max(data.count - 1, 1))) * geometry.size.width
                        Text(formatHour(data[index].time))
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                            .position(x: x, y: geometry.size.height - 10)
                    }
                }
            }
        }
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview
#Preview("UV Forecast Popup") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                Button("Show Forecast") {
                    isPresented = true
                }

                UVForecastPopup(
                    isPresented: $isPresented,
                    uvForecast: PreviewData.sampleUVForecast
                )
            }
        }
    }

    return PreviewWrapper()
}
