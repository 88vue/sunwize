import SwiftUI
import SceneKit

enum BottomViewMode {
    case none
    case timeline
    case form
}

struct BodyScanView: View {
    @StateObject private var viewModel = BodyScanViewModel()
    @State private var selectedSpot: BodySpot?
    @State private var bottomViewMode: BottomViewMode = .none
    @State private var selectedLocation: LocationData?
    @State private var isModelLoading = true
    
    struct LocationData {
        let coordinates: SIMD3<Float>
        let bodyPart: String
        var spots: [BodySpot]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (hide when form is full screen)
            if bottomViewMode != .form {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Body Scan Tracker")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("\(viewModel.bodySpots.count) spots tracked")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "figure.stand")
                        .font(.title)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            
            // 3D Model Section (hide when form is full screen)
            if bottomViewMode != .form {
                ZStack {
                    BodyModel3DView(
                        spotMarkers: viewModel.spotMarkers,
                        isInteractive: true,
                        onModelTap: handleModelTap,
                        onSpotTap: handleSpotTap,
                        isLoading: $isModelLoading
                    )
                    
                    // Loading overlay
                    if isModelLoading {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading 3D Model...")
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding(.top, 10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                    }
                    
                    // Instructions
                    if !isModelLoading {
                        VStack {
                            Spacer()
                            Text("Double tap to add a new spot or zoom and tap orange dots to view existing spots")
                                .font(.callout)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(12)
                                .padding()
                        }
                    }
                }
                .frame(maxHeight: bottomViewMode == .none ? .infinity : UIScreen.main.bounds.height * 0.6)
                .padding(.horizontal)
            }
            
            // Bottom Section (Timeline or Form)
            if bottomViewMode != .none {
                VStack(spacing: 0) {
                    if bottomViewMode == .timeline, let location = selectedLocation {
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
                            onClose: closeBottomView,
                            onSpotTap: { spot in
                                selectedSpot = spot
                            }
                        )
                        .background(Color(.systemBackground))
                        .cornerRadius(20, corners: [.topLeft, .topRight])
                        .shadow(color: .black.opacity(0.1), radius: 5, y: -2)
                        .frame(height: 160)
                    }
                    
                    if bottomViewMode == .form, let location = selectedLocation {
                        InlineSpotFormView(
                            coordinates: location.coordinates,
                            existingLocation: nil,
                            onSave: saveBodySpot,
                            onCancel: closeBottomView
                        )
                        .background(Color(.systemBackground))
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            Task {
                await viewModel.loadBodyScans()
            }
        }
        .sheet(item: $selectedSpot) { spot in
            SpotDetailView(spot: spot, onDelete: {
                Task {
                    await viewModel.deleteSpot(spot)
                    selectedSpot = nil
                    // Update selected location spots
                    if var location = selectedLocation {
                        location.spots = location.spots.filter { $0.id != spot.id }
                        if location.spots.isEmpty {
                            closeBottomView()
                        } else {
                            selectedLocation = location
                        }
                    }
                }
            })
        }
    }
    
    // MARK: - Helper Functions
    
    private func handleModelTap(_ coordinates: SIMD3<Float>) {
        let bodyPart = BodyPart.from(coordinates: coordinates).rawValue
        selectedLocation = LocationData(
            coordinates: coordinates,
            bodyPart: bodyPart,
            spots: []
        )
        bottomViewMode = .form
    }
    
    private func handleSpotTap(_ coordinates: SIMD3<Float>, _ bodyPart: String) {
        // Find spots at this location
        let tolerance: Float = 0.3
        let spotsAtLocation = viewModel.bodySpots.filter { spot in
            guard let location = viewModel.bodyLocations.first(where: { $0.id.uuidString == spot.locationId.uuidString }) else {
                return false
            }
            let distance = simd_distance(location.coordinates, coordinates)
            return distance < tolerance
        }
        
        if !spotsAtLocation.isEmpty {
            selectedLocation = LocationData(
                coordinates: coordinates,
                bodyPart: bodyPart,
                spots: spotsAtLocation
            )
            bottomViewMode = .timeline
        }
    }
    
    private func handleAddNewLogToLocation() {
        if selectedLocation != nil {
            bottomViewMode = .form
        }
    }
    
    private func closeBottomView() {
        bottomViewMode = .none
        selectedLocation = nil
    }
    
    private func saveBodySpot(_ spotData: SpotFormData) {
        Task {
            await viewModel.saveSpot(spotData)
            
            // Update the location data
            if var location = selectedLocation {
                // Refresh spots for this location
                if let savedSpot = viewModel.bodySpots.last {
                    location.spots.append(savedSpot)
                    selectedLocation = location
                }
            }
            
            bottomViewMode = .timeline
        }
    }
}

// MARK: - Rounded Corner Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}