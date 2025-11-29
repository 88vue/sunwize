import SwiftUI

/// Main UV exposure page layout
struct UVExposurePage: View {
    // MARK: - Properties
    @ObservedObject var viewModel: UVTrackingViewModel
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var profileViewModel: ProfileViewModel

    @Binding var showingStreakPopup: Bool
    @Binding var showingForecastPopup: Bool
    @Binding var showingSunscreenPopup: Bool

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. UV Index + Streak Island (always visible)
                // Uses displayUVIndex which refreshes every 15 min regardless of indoor/outdoor
                UVIndexIsland(
                    uvIndex: viewModel.displayUVIndex,
                    streak: viewModel.uvSafeStreak,
                    onStreakTap: {
                        withAnimation {
                            showingStreakPopup = true
                        }
                    }
                )

                // 2. Current State Container
                currentStateView()
                    .animation(.stateTransition, value: locationManager.locationMode)
                    .animation(.stateTransition, value: viewModel.isDaytime)
                    .animation(.stateTransition, value: viewModel.sunscreenActive)

                
                // 4. Action Island (conditional)
                if shouldShowActions() {
                    ActionIsland(
                        showSunscreen: !viewModel.sunscreenActive,
                        showUnderCover: true,
                        onApplySunscreen: {
                            withAnimation {
                                showingSunscreenPopup = true
                            }
                        },
                        onUnderCover: {
                            viewModel.setManualIndoorOverride(duration: 900) // 15 minutes
                        }
                    )
                    .transition(.islandSlide)
                }

                // 5. Reapply Sunscreen Button (when sunsafe)
                if viewModel.sunscreenActive && locationManager.locationMode == .outside && viewModel.isDaytime {
                    PrimaryButton(
                        title: "Reapply Sunscreen",
                        icon: "sun.max",
                        style: .primary,
                        action: {
                            withAnimation {
                                showingSunscreenPopup = true
                            }
                        }
                    )
                    .transition(.islandSlide)
                }

                // 3. UV Forecast Island (always visible)
                ForecastIsland(
                    uvForecast: viewModel.uvForecast,
                    onViewFullForecast: {
                        withAnimation {
                            showingForecastPopup = true
                        }
                    }
                )

            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, 95)
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Current State View
    @ViewBuilder
    private func currentStateView() -> some View {
        // Night time overrides all other states
        if !viewModel.isDaytime {
            NightTimeStateView(
                sunsetTime: viewModel.sunsetTime,
                sunriseTime: viewModel.sunriseTime
            )
        }
        // Sunscreen active shows sunsafe state (only when outside)
        else if viewModel.sunscreenActive && locationManager.locationMode == .outside {
            SunSafeStateView(
                spf: 30, // Hardcoded for now per plan
                appliedTime: viewModel.sunscreenAppliedTime ?? Date(),
                reapplyTime: (viewModel.sunscreenAppliedTime ?? Date()).addingTimeInterval(AppConfig.sunscreenProtectionDuration),
                onReapply: {
                    withAnimation {
                        showingSunscreenPopup = true
                    }
                }
            )
        }
        // Standard location mode states
        else {
            switch locationManager.locationMode {
            case .outside:
                OutsideStateView(
                    sessionSED: viewModel.sessionSED,
                    exposureRatio: viewModel.exposureRatio,
                    sessionStartTime: viewModel.sessionStartTime,
                    med: profileViewModel.profile.med
                )

            case .inside:
                InsideStateView()

            case .vehicle:
                VehicleStateView()

            case .unknown:
                UnknownStateView(
                    reason: locationManager.uncertaintyReason?.rawValue,
                    onRetry: {
                        Task {
                            _ = try? await locationManager.getCurrentState(forceRefresh: true)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Helper Methods
    private func shouldShowActions() -> Bool {
        // Only show actions when outside and during daytime (and not sunsafe)
        return viewModel.isDaytime &&
               locationManager.locationMode == .outside &&
               !viewModel.sunscreenActive
    }
}
