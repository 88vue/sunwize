import SwiftUI
// Note: Charts framework requires iOS 16+
// If targeting iOS 15, use a third-party charting library or custom implementation
#if canImport(Charts)
import Charts
#endif

struct UVForecastView: View {
    let uvData: [UVForecastData]
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    
    // Split forecast data into 24-hour chunks
    private var forecastPages: [[UVForecastData]] {
        let chunked = uvData.chunked(into: 24)
        return chunked
    }
    
    private var totalPages: Int {
        forecastPages.count
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with page indicator
                VStack(spacing: 12) {
                    HStack {
                        Text(pageTitle)
                            .font(.headline)
                        Spacer()
                        Text("\(currentPage + 1) / \(totalPages)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Page dots indicator
                    if totalPages > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<min(totalPages, 5), id: \.self) { index in
                                Circle()
                                    .fill(currentPage == index ? Color.orange : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                
                // Swipeable chart pages
                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { pageIndex in
                        ForecastPageView(
                            uvData: forecastPages[pageIndex],
                            pageIndex: pageIndex
                        )
                        .tag(pageIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 280)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Peak UV time for current page
                        if !forecastPages.isEmpty && currentPage < forecastPages.count {
                            let currentPageData = forecastPages[currentPage]
                            if let peak = currentPageData.max(by: { $0.uvIndex < $1.uvIndex }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Peak UV Time")
                                        .font(.headline)

                                    HStack {
                                        Image(systemName: "sun.max.fill")
                                            .foregroundColor(.orange)
                                        Text("\(peak.time, format: .dateTime.hour().minute())")
                                            .font(.subheadline)
                                        Spacer()
                                        Text("UV Index: \(String(format: "%.1f", peak.uvIndex))")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .padding()
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                            }
                        }

                        // UV Level Breakdown
                        VStack(alignment: .leading, spacing: 12) {
                            Text("UV Index Guide")
                                .font(.headline)

                            ForEach([
                                (level: UVIndexLevel.low, range: "0-2"),
                                (level: UVIndexLevel.moderate, range: "3-5"),
                                (level: UVIndexLevel.high, range: "6-7"),
                                (level: UVIndexLevel.veryHigh, range: "8-10"),
                                (level: UVIndexLevel.extreme, range: "11+")
                            ], id: \.range) { item in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: item.level.color) ?? .gray)
                                        .frame(width: 12, height: 12)

                                    Text("\(item.range)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(width: 40, alignment: .leading)

                                    Text(item.level.description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("UV Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var pageTitle: String {
        guard currentPage < forecastPages.count,
              let firstDate = forecastPages[currentPage].first?.time else {
            return "UV Forecast"
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(firstDate) {
            return "Today's Forecast"
        } else if calendar.isDateInTomorrow(firstDate) {
            return "Tomorrow's Forecast"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: firstDate)
        }
    }
}

// MARK: - Forecast Page View
struct ForecastPageView: View {
    let uvData: [UVForecastData]
    let pageIndex: Int
    
    var body: some View {
        VStack(spacing: 0) {
            if !uvData.isEmpty {
                #if canImport(Charts)
                if #available(iOS 16.0, *) {
                    Chart(uvData) { item in
                        LineMark(
                            x: .value("Time", item.time),
                            y: .value("UV Index", item.uvIndex)
                        )
                        .foregroundStyle(Color.orange)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", item.time),
                            y: .value("UV Index", item.uvIndex)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 240)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            if let date = value.as(Date.self) {
                                let hour = Calendar.current.component(.hour, from: date)
                                let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
                                let period = hour < 12 ? "am" : "pm"
                                AxisValueLabel {
                                    Text("\(displayHour)\(period)")
                                        .font(.caption)
                                }
                            }
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let uv = value.as(Double.self) {
                                    Text("\(Int(uv))")
                                        .font(.caption)
                                }
                            }
                            AxisGridLine()
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Fallback for iOS 15
                    SimpleForecastChart(uvData: uvData)
                        .frame(height: 240)
                        .padding(.horizontal)
                }
                #else
                SimpleForecastChart(uvData: uvData)
                    .frame(height: 240)
                    .padding(.horizontal)
                #endif
            } else {
                Text("No forecast data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Simple fallback chart for iOS 15
struct SimpleForecastChart: View {
    let uvData: [UVForecastData]

    var maxUV: Double {
        uvData.map { $0.uvIndex }.max() ?? 10
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Background grid
                ForEach(0..<5) { index in
                    let y = geometry.size.height * (1 - Double(index) / 4)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                }

                // UV line
                Path { path in
                    guard !uvData.isEmpty else { return }

                    let xStep = geometry.size.width / CGFloat(uvData.count - 1)

                    for (index, item) in uvData.enumerated() {
                        let x = CGFloat(index) * xStep
                        let y = geometry.size.height * (1 - item.uvIndex / maxUV)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.orange, lineWidth: 2)
            }
        }
    }
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Color hex extension moved to Extensions/Color+Hex.swift