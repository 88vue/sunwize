import SwiftUI
import UIKit
#if canImport(Charts)
import Charts
#endif

struct UVTrackingView: View {
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var viewModel = UVTrackingViewModel()

    @State private var currentPage = 0
    @State private var showingUVForecast = false
    @State private var showingUVHistory = false
    @State private var showingVitaminDHistory = false
    @State private var showingTargetEditor = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background color
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<2) { index in
                            Circle()
                                .fill(currentPage == index ? Color.orange : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.vertical, 12)

                    // Swipeable pages
                    TabView(selection: $currentPage) {
                        UVExposurePage(
                            viewModel: viewModel,
                            showingForecast: $showingUVForecast,
                            showingHistory: $showingUVHistory
                        )
                        .tag(0)

                        VitaminDPage(
                            viewModel: viewModel,
                            showingHistory: $showingVitaminDHistory,
                            showingTargetEditor: $showingTargetEditor
                        )
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle(currentPage == 0 ? "UV Exposure" : "Vitamin D")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.startTracking(profile: profileViewModel.profile)
                
                // Retry loading forecast after a short delay if LocationManager needs time to get location
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    if viewModel.uvForecast.isEmpty {
                        await viewModel.retryLoadForecast()
                    }
                }
            }
            .onDisappear {
                viewModel.stopTracking()
            }
        }
        .sheet(isPresented: $showingUVForecast) {
            UVForecastView(uvData: viewModel.uvForecast)
        }
        .sheet(isPresented: $showingUVHistory) {
            UVHistoryView(history: viewModel.uvHistory)
        }
        .sheet(isPresented: $showingVitaminDHistory) {
            VitaminDHistoryView(
                history: viewModel.vitaminDHistory,
                targetIU: viewModel.vitaminDTarget
            )
        }
        .sheet(isPresented: $showingTargetEditor) {
            VitaminDTargetEditor(currentTarget: viewModel.vitaminDTarget) { newTarget in
                viewModel.updateVitaminDTarget(newTarget)
            }
        }
    }
}

// MARK: - UV Exposure Page
struct UVExposurePage: View {
    @ObservedObject var viewModel: UVTrackingViewModel
    @Binding var showingForecast: Bool
    @Binding var showingHistory: Bool
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        VStack(spacing: 20) {
            // UV Safe Streak
            HStack {
                Spacer()
                StreakBadge(
                    value: viewModel.uvSafeStreak,
                    label: "UV Safe Streak",
                    icon: "shield.fill",
                    color: .green
                )
                .onTapGesture {
                    showingHistory = true
                }
            }
            .padding(.horizontal)

            // Main content based on location mode
            Group {
                // Check nighttime first, regardless of location mode
                if !viewModel.isDaytime {
                    NightTimeView(
                        showingForecast: $showingForecast,
                        uvForecast: viewModel.uvForecast
                    )
                } else {
                    switch locationManager.locationMode {
                    case .outside:
                        OutsideView(viewModel: viewModel, showingForecast: $showingForecast)

                    case .inside:
                        InsideView(
                            title: "Looks like you're inside",
                            uvIndex: viewModel.currentUVIndex,
                            showingForecast: $showingForecast,
                            uvForecast: viewModel.uvForecast
                        )

                    case .vehicle:
                        InsideView(
                            title: "Looks like you're in a vehicle",
                            uvIndex: viewModel.currentUVIndex,
                            showingForecast: $showingForecast,
                            uvForecast: viewModel.uvForecast
                        )

                    case .unknown:
                        if !viewModel.isUVTrackingEnabled {
                            DisabledView(feature: "UV Tracking")
                        } else {
                            UnknownLocationView(
                                reason: locationManager.uncertaintyReason,
                                confidence: locationManager.confidence,
                                showingForecast: $showingForecast,
                                onRetry: {
                                    Task {
                                        _ = try? await locationManager.getCurrentState(forceRefresh: true)
                                    }
                                }
                            )
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Outside View
struct OutsideView: View {
    @ObservedObject var viewModel: UVTrackingViewModel
    @Binding var showingForecast: Bool

    var body: some View {
        VStack(spacing: 30) {
            // UV Index Display
            VStack(spacing: 8) {
                Text("UV Index")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text(String(format: "%.1f", viewModel.currentUVIndex))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(uvIndexColor(viewModel.currentUVIndex))

                HStack(spacing: 4) {
                    Text(UVIndexLevel.from(uvIndex: viewModel.currentUVIndex).description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.05))
            .cornerRadius(16)
            .onTapGesture {
                showingForecast = true
            }

            // Battery Indicator - Hidden when sunscreen is active
            if !viewModel.sunscreenActive {
                BatteryIndicator(
                    progress: viewModel.exposureRatio,
                    gradient: true
                )
                .frame(height: 60)
                .padding(.horizontal, 40)
            }

            // Session info
            VStack(spacing: 12) {
                if let sessionStart = viewModel.sessionStartTime {
                    Label(
                        "Started at \(sessionStart, formatter: timeFormatter)",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if viewModel.sunscreenActive {
                    SunscreenTimer(
                        appliedTime: viewModel.sunscreenAppliedTime ?? Date(),
                        onReapply: {
                            viewModel.applySunscreen()
                        },
                        onExpire: {
                            viewModel.clearExpiredSunscreen()
                        }
                    )
                } else {
                    Button(action: {
                        viewModel.applySunscreen()
                    }) {
                        Label("Apply Sunscreen", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: 200)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }

            // Recommendations
            if viewModel.exposureRatio > 0.75 {
                RecommendationCard(
                    text: viewModel.exposureRatio >= 1.0 ?
                        "⚠️ You've exceeded your safe UV limit! Seek shade immediately." :
                        "You're approaching your UV limit. Consider applying sunscreen or going inside.",
                    color: viewModel.exposureRatio >= 1.0 ? .red : .orange
                )
                .padding(.horizontal)
            }
        }
    }

    private func uvIndexColor(_ index: Double) -> Color {
        switch UVIndexLevel.from(uvIndex: index) {
        case .low:
            return .green
        case .moderate:
            return .yellow
        case .high:
            return .orange
        case .veryHigh:
            return Color(red: 1.0, green: 0.4, blue: 0.0)
        case .extreme:
            return .red
        }
    }
}

// MARK: - Inside View
struct InsideView: View {
    let title: String
    let uvIndex: Double
    @Binding var showingForecast: Bool
    let uvForecast: [UVForecastData]
    
    // Filter to next 24 hours from now
    private var next24Hours: [UVForecastData] {
        let now = Date()
        let endTime = now.addingTimeInterval(24 * 3600)
        return uvForecast.filter { $0.time >= now && $0.time <= endTime }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "house.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Current UV Index: \(String(format: "%.1f", uvIndex))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Embedded forecast chart
            if !next24Hours.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Next 24 Hours")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            showingForecast = true
                        }) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    #if canImport(Charts)
                    if #available(iOS 16.0, *) {
                        Chart(next24Hours) { item in
                            LineMark(
                                x: .value("Time", item.time),
                                y: .value("UV Index", item.uvIndex)
                            )
                            .foregroundStyle(Color.orange)
                            .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 150)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                                if let date = value.as(Date.self) {
                                    let hour = Calendar.current.component(.hour, from: date)
                                    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
                                    let period = hour < 12 ? "am" : "pm"
                                    AxisValueLabel {
                                        Text("\(displayHour)\(period)")
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let uv = value.as(Double.self) {
                                        Text("\(Int(uv))")
                                    }
                                }
                            }
                        }
                    } else {
                        SimpleForecastChart(uvData: next24Hours)
                            .frame(height: 150)
                    }
                    #else
                    SimpleForecastChart(uvData: next24Hours)
                        .frame(height: 150)
                    #endif
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            } else {
                Button(action: {
                    showingForecast = true
                }) {
                    Label("View UV Forecast", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }
}

// MARK: - Night Time View
struct NightTimeView: View {
    @Binding var showingForecast: Bool
    let uvForecast: [UVForecastData]
    
    // Filter to tomorrow's forecast (next 24 hours starting from midnight tomorrow)
    private var tomorrowForecast: [UVForecastData] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowStart = calendar.startOfDay(for: tomorrow)
        let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart
        
        return uvForecast.filter { $0.time >= tomorrowStart && $0.time < tomorrowEnd }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 60))
                .foregroundColor(.indigo)

            Text("Looks like it's night time")
                .font(.title2)
                .fontWeight(.semibold)

            Text("No UV exposure at night")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Embedded forecast chart for tomorrow
            if !tomorrowForecast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Tomorrow's Forecast")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            showingForecast = true
                        }) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    #if canImport(Charts)
                    if #available(iOS 16.0, *) {
                        Chart(tomorrowForecast) { item in
                            LineMark(
                                x: .value("Time", item.time),
                                y: .value("UV Index", item.uvIndex)
                            )
                            .foregroundStyle(Color.orange)
                            .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 150)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                                if let date = value.as(Date.self) {
                                    let hour = Calendar.current.component(.hour, from: date)
                                    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
                                    let period = hour < 12 ? "am" : "pm"
                                    AxisValueLabel {
                                        Text("\(displayHour)\(period)")
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let uv = value.as(Double.self) {
                                        Text("\(Int(uv))")
                                    }
                                }
                            }
                        }
                    } else {
                        SimpleForecastChart(uvData: tomorrowForecast)
                            .frame(height: 150)
                    }
                    #else
                    SimpleForecastChart(uvData: tomorrowForecast)
                        .frame(height: 150)
                    #endif
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            } else {
                Button(action: {
                    showingForecast = true
                }) {
                    Label("View Full Forecast", systemImage: "sun.max.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }
}

// MARK: - Vitamin D Page
struct VitaminDPage: View {
    @ObservedObject var viewModel: UVTrackingViewModel
    @Binding var showingHistory: Bool
    @Binding var showingTargetEditor: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header with badges
            HStack {
                TargetBadge(
                    current: viewModel.currentVitaminD,
                    target: viewModel.vitaminDTarget,
                    onTap: {
                        showingTargetEditor = true
                    }
                )

                Spacer()

                StreakBadge(
                    value: viewModel.vitaminDStreak,
                    label: "Vitamin D Streak",
                    icon: "sparkles",
                    color: .yellow
                )
                .onTapGesture {
                    showingHistory = true
                }
            }
            .padding(.horizontal)

            // Main content
            if viewModel.isVitaminDTrackingEnabled {
                VStack(spacing: 30) {
                    // Battery Indicator
                    BatteryIndicator(
                        progress: viewModel.vitaminDProgress,
                        gradient: false,
                        color: .yellow
                    )
                    .frame(height: 60)
                    .padding(.horizontal, 40)

                    // Current IU
                    VStack(spacing: 8) {
                        Text("\(Int(viewModel.currentVitaminD)) IU")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("of \(Int(viewModel.vitaminDTarget)) IU daily target")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Body Exposure Slider
                    BodyExposureSlider(
                        value: $viewModel.bodyExposureFactor,
                        onChange: { newValue in
                            viewModel.updateBodyExposure(newValue)
                        }
                    )
                    .padding(.horizontal)
                }
            } else {
                DisabledView(feature: "Vitamin D Tracking")
            }

            Spacer()
        }
    }
}

// MARK: - Helper Views
struct UnknownLocationView: View {
    let reason: LocationManager.LocationUncertaintyReason?
    let confidence: Double
    @Binding var showingForecast: Bool
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(confidenceLabel)
                .font(.footnote)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Retry Detection", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .cornerRadius(12)
                }

                Button(action: {
                    showingForecast = true
                }) {
                    Label("View UV Forecast", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                }

                if shouldShowSettingsButton {
                    Button(action: openSettings) {
                        Label("Check Location Settings", systemImage: "location")
                            .font(.headline)
                            .foregroundColor(.orange)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
    }

    private var title: String {
        switch reason {
        case .buildingDataUnavailable:
            return "We're still learning this area"
        case .poorGPSAccuracy:
            return "Location signal is weak"
        case .insufficientEvidence:
            return "Need more evidence"
        case .none:
            return "Detecting your location"
        }
    }

    private var description: String {
        switch reason {
        case .buildingDataUnavailable:
            return "Stay connected for a moment while we download nearby building outlines or move outside briefly."
        case .poorGPSAccuracy:
            return "Try moving closer to a window or heading outdoors so we can lock onto a stronger GPS signal."
        case .insufficientEvidence:
            return "Take a few steps or wait a moment while we gather motion and location data to confirm your status."
        case .none:
            return "Hang tight—we're double-checking your location before sending any UV alerts."
        }
    }

    private var confidenceLabel: String {
        let clamped = min(max(confidence, 0), 1)
        return "Detection confidence \(Int(clamped * 100))%"
    }

    private var shouldShowSettingsButton: Bool {
        reason == .poorGPSAccuracy
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Detecting location...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct DisabledView: View {
    let feature: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("\(feature) is disabled")
                .font(.title3)
                .fontWeight(.semibold)

            NavigationLink(destination: ProfileView()) {
                Text("Enable in Settings")
                    .font(.headline)
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }
}

struct RecommendationCard: View {
    let text: String
    let color: Color

    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding()
        .background(color)
        .cornerRadius(12)
    }
}

// MARK: - Formatters
private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
}()