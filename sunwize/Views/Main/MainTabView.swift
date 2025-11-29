import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var locationManager: LocationManager

    @StateObject private var bodySpotViewModel = BodySpotViewModel()
    @StateObject private var bodySpotUIState = BodySpotUIState()
    @StateObject private var uvTrackingViewModel = UVTrackingViewModel()

    // Profile popup state
    @State private var showingEditProfile = false

    // UV Tracking popup states
    @State private var showingStreakPopup = false
    @State private var showingForecastPopup = false
    @State private var showingSunscreenPopup = false
    @State private var showingVitaminDHistory = false
    @State private var showingTargetEditor = false

    private let tabBarHeight: CGFloat = 90

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content view based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    BodySpotView(viewModel: bodySpotViewModel, uiState: bodySpotUIState)
                case 1:
                    UVTrackingView(
                        viewModel: uvTrackingViewModel,
                        showingStreakPopup: $showingStreakPopup,
                        showingForecastPopup: $showingForecastPopup,
                        showingSunscreenPopup: $showingSunscreenPopup,
                        showingVitaminDHistory: $showingVitaminDHistory,
                        showingTargetEditor: $showingTargetEditor
                    )
                case 2:
                    ProfileView(showingEditProfile: $showingEditProfile)
                default:
                    UVTrackingView(
                        viewModel: uvTrackingViewModel,
                        showingStreakPopup: $showingStreakPopup,
                        showingForecastPopup: $showingForecastPopup,
                        showingSunscreenPopup: $showingSunscreenPopup,
                        showingVitaminDHistory: $showingVitaminDHistory,
                        showingTargetEditor: $showingTargetEditor
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: tabBarHeight)
            }

            // Custom Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
                .edgesIgnoringSafeArea(.bottom)
            
            // Overlay: Timeline popup (overlays the content and tab bar)
            if let location = bodySpotUIState.selectedLocation {
                BottomSheetOverlay(
                    isPresented: bodySpotUIState.bottomViewMode == .timeline,
                    onDismiss: {
                        bodySpotUIState.closeBottomView()
                    }
                ) {
                    SpotTimelineView(
                        location: BodyLocation(
                            id: UUID(),
                            userId: UUID(),
                            coordX: Double(location.coordinates.x),
                            coordY: Double(location.coordinates.y),
                            coordZ: Double(location.coordinates.z),
                            bodyPart: location.bodyPart,
                            createdAt: Date()
                        ),
                        spots: location.spots,
                        onAddNew: handleAddNewLogToLocation,
                        onClose: bodySpotUIState.closeBottomView,
                        onSpotTap: { spot in
                            withAnimation(.scaleInOutEase) {
                                bodySpotUIState.selectedSpot = spot
                            }
                        }
                    )
                }
            }

            // Overlay: Add Spot Form (overlays everything including timeline and tab bar)
            if let location = bodySpotUIState.selectedLocation {
                BottomSheetOverlay(
                    isPresented: bodySpotUIState.bottomViewMode == .form,
                    onDismiss: {
                        // If we have existing spots, go back to timeline, otherwise close
                        if !location.spots.isEmpty {
                            withAnimation {
                                bodySpotUIState.bottomViewMode = .timeline
                            }
                        } else {
                            bodySpotUIState.closeBottomView()
                        }
                    }
                ) {
                    InlineSpotFormView(
                        coordinates: location.coordinates,
                        existingLocation: nil,
                        onSave: saveBodySpot,
                        onCancel: {
                            // If we have existing spots, go back to timeline, otherwise close
                            if !location.spots.isEmpty {
                                withAnimation {
                                    bodySpotUIState.bottomViewMode = .timeline
                                }
                            } else {
                                bodySpotUIState.closeBottomView()
                            }
                        }
                    )
                }
            }
            
            // Overlay: Spot Detail Popup (overlays everything)
            if let spot = bodySpotUIState.selectedSpot {
                // Backdrop
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.scaleInOutEase))
                    .onTapGesture {
                        withAnimation(.scaleInOutEase) {
                            bodySpotUIState.selectedSpot = nil
                        }
                    }
                    .zIndex(4)

                SpotDetailView(
                    spot: spot,
                    onDelete: {
                        Task {
                            await bodySpotViewModel.deleteSpot(spot)
                            withAnimation(.scaleInOutEase) {
                                bodySpotUIState.selectedSpot = nil
                            }

                            // Update selected location spots
                            if var location = bodySpotUIState.selectedLocation {
                                location.spots = location.spots.filter { $0.id != spot.id }
                                if location.spots.isEmpty {
                                    bodySpotUIState.closeBottomView()
                                } else {
                                    bodySpotUIState.selectedLocation = location
                                }
                            }
                        }
                    },
                    onClose: {
                        withAnimation(.scaleInOutEase) {
                            bodySpotUIState.selectedSpot = nil
                        }
                    }
                )
                .zIndex(5)
                .transition(.scaleInOut)
            }

            // MARK: - Profile Popups

            // Overlay: Edit Profile Popup
            BottomSheetOverlay(
                isPresented: showingEditProfile,
                onDismiss: {
                    withAnimation {
                        showingEditProfile = false
                    }
                }
            ) {
                EditProfilePopup(
                    isPresented: $showingEditProfile,
                    profile: profileViewModel.profile,
                    onSave: { updatedProfile in
                        Task {
                            try? await authService.updateProfile(updatedProfile)
                            profileViewModel.profile = updatedProfile
                        }
                    }
                )
            }

            // MARK: - UV Tracking Popups

            // Overlay: Streak Popup
            BottomSheetOverlay(
                isPresented: showingStreakPopup,
                onDismiss: {
                    withAnimation {
                        showingStreakPopup = false
                    }
                }
            ) {
                UVSafeStreakPopup(
                    isPresented: $showingStreakPopup,
                    currentStreak: uvTrackingViewModel.uvSafeStreak,
                    weeklyHistory: uvTrackingViewModel.uvHistory.map { ($0.date, $0.isSafe) }
                )
            }

            // Overlay: Forecast Popup
            BottomSheetOverlay(
                isPresented: showingForecastPopup,
                onDismiss: {
                    withAnimation {
                        showingForecastPopup = false
                    }
                }
            ) {
                UVForecastPopup(
                    isPresented: $showingForecastPopup,
                    uvForecast: uvTrackingViewModel.uvForecast
                )
            }

            // Overlay: Sunscreen Popup
            BottomSheetOverlay(
                isPresented: showingSunscreenPopup,
                onDismiss: {
                    withAnimation {
                        showingSunscreenPopup = false
                    }
                }
            ) {
                ApplySunscreenPopup(
                    isPresented: $showingSunscreenPopup,
                    onConfirm: { spf, time in
                        uvTrackingViewModel.applySunscreen()
                    }
                )
            }

            // Overlay: Vitamin D History Popup
            BottomSheetOverlay(
                isPresented: showingVitaminDHistory,
                onDismiss: {
                    withAnimation {
                        showingVitaminDHistory = false
                    }
                }
            ) {
                VitaminDHistoryPopup(
                    isPresented: $showingVitaminDHistory,
                    history: uvTrackingViewModel.vitaminDHistory,
                    targetIU: uvTrackingViewModel.vitaminDTarget
                )
            }

            // Overlay: Edit Target Popup
            BottomSheetOverlay(
                isPresented: showingTargetEditor,
                onDismiss: {
                    withAnimation {
                        showingTargetEditor = false
                    }
                }
            ) {
                EditTargetPopup(
                    isPresented: $showingTargetEditor,
                    targetIU: $uvTrackingViewModel.vitaminDTarget,
                    onSave: { newTarget in
                        uvTrackingViewModel.updateVitaminDTarget(newTarget)
                    }
                )
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
    
    // MARK: - Helper Functions
    
    private func handleAddNewLogToLocation() {
        if bodySpotUIState.selectedLocation != nil {
            withAnimation {
                bodySpotUIState.bottomViewMode = .form
            }
        }
    }
    
    private func saveBodySpot(_ spotData: SpotFormData) {
        Task {
            await bodySpotViewModel.saveSpot(spotData)
            
            // Update the location data
            if var location = bodySpotUIState.selectedLocation {
                // Refresh spots for this location
                if let savedSpot = bodySpotViewModel.bodySpots.last {
                    location.spots.append(savedSpot)
                    bodySpotUIState.selectedLocation = location
                }
            }
            
            withAnimation {
                bodySpotUIState.bottomViewMode = .timeline
            }
        }
    }
}
