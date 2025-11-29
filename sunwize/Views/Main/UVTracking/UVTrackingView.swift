import SwiftUI

// MARK: - Main UV Tracking View
struct UVTrackingView: View {
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var locationManager: LocationManager
    @ObservedObject var viewModel: UVTrackingViewModel

    @State private var currentPage = 0

    // Popup bindings (managed by MainTabView)
    @Binding var showingStreakPopup: Bool
    @Binding var showingForecastPopup: Bool
    @Binding var showingSunscreenPopup: Bool
    @Binding var showingVitaminDHistory: Bool
    @Binding var showingTargetEditor: Bool

    var body: some View {
        ZStack {
            // Background color
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ZStack(alignment: .top) {
                // Swipeable pages
                TabView(selection: $currentPage) {
                    UVExposurePage(
                        viewModel: viewModel,
                        showingStreakPopup: $showingStreakPopup,
                        showingForecastPopup: $showingForecastPopup,
                        showingSunscreenPopup: $showingSunscreenPopup
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

                // UV/Vitamin D Toggle (edge-to-edge background with rounded bottom corners)
                ZStack(alignment: .bottom) {
                    Color.white
                        .clipShape(RoundedCorner(radius: 24, corners: [.bottomLeft, .bottomRight]))
                        .shadow(color: .black.opacity(0.1), radius: 7.5, x: 0, y: 10)
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 4)
                        .ignoresSafeArea(edges: .top)

                    UVToggle(selection: $currentPage)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.bottom, 20)
                }
                .frame(height: 65) // Toggle height (45) + bottom padding (12) + safe area spacing (8)
            }
        }
            .onAppear {
                // Defer to next run loop to avoid "Publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    viewModel.startTracking(profile: profileViewModel.profile)
                }

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
}
