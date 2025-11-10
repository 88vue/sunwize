import Foundation
import SwiftUI
import PhotosUI
import CoreLocation

@MainActor
class BodyScanViewModel: ObservableObject {
    @Published var bodyLocations: [BodyLocation] = []
    @Published var bodySpots: [BodySpot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared
    private var userId: UUID?

    init() {
        loadUserId()
    }

    private func loadUserId() {
        if let userIdString = UserDefaults.standard.string(forKey: "user_id"),
           let uuid = UUID(uuidString: userIdString) {
            userId = uuid
        }
    }
    
    // MARK: - Computed Properties
    
    /// Grouped spots by location for creating markers
    var groupedSpotsByLocation: [String: (location: BodyLocation, spots: [BodySpot])] {
        var groups: [String: (location: BodyLocation, spots: [BodySpot])] = [:]
        
        for spot in bodySpots {
            if let location = bodyLocations.first(where: { $0.id == spot.locationId }) {
                let key = "\(location.coordX)-\(location.coordY)-\(location.coordZ)"
                if groups[key] == nil {
                    groups[key] = (location: location, spots: [])
                }
                groups[key]?.spots.append(spot)
            }
        }
        
        return groups
    }
    
    /// Convert grouped spots to markers for 3D display
    var spotMarkers: [SpotMarker] {
        return groupedSpotsByLocation.map { key, value in
            SpotMarker(
                id: key,
                position: SIMD3<Float>(
                    Float(value.location.coordX),
                    Float(value.location.coordY),
                    Float(value.location.coordZ)
                ),
                bodyPart: value.location.bodyPart ?? "Unknown",
                spotCount: value.spots.count
            )
        }
    }

    // MARK: - Data Loading
    
    func loadBodyScans() async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = userId else {
            errorMessage = "User not authenticated"
            return
        }

        do {
            // Load all body locations for user
            bodyLocations = try await supabase.getBodyLocations(userId: userId)

            // Load spots for all locations
            var allSpots: [BodySpot] = []
            for location in bodyLocations {
                let spots = try await supabase.getBodySpots(locationId: location.id)
                allSpots.append(contentsOf: spots)
            }
            bodySpots = allSpots
        } catch {
            errorMessage = "Failed to load body scans: \(error.localizedDescription)"
            print("❌ Error loading body scans: \(error)")
        }
    }

    // MARK: - Helper Methods
    
    func getSpotsForLocation(_ location: BodyLocation) -> [BodySpot] {
        return bodySpots.filter { $0.locationId == location.id }
    }

    func findNearbyLocation(coordinates: SIMD3<Float>) -> BodyLocation? {
        let tolerance: Float = 0.3
        return bodyLocations.first { location in
            simd_distance(location.coordinates, coordinates) < tolerance
        }
    }
    
    // MARK: - Data Mutation

    func saveSpot(_ spotData: SpotFormData) async {
        isLoading = true
        defer { isLoading = false }

        guard let userId = userId else {
            errorMessage = "User not authenticated"
            return
        }

        do {
            // Create or find location
            let location: BodyLocation
            if let existingLocation = spotData.location {
                location = existingLocation
            } else {
                // Check for nearby location first
                if let nearbyLocation = findNearbyLocation(coordinates: spotData.coordinates) {
                    location = nearbyLocation
                } else {
                    // Create new location
                    let newLocation = BodyLocation(
                        id: UUID(),
                        userId: userId,
                        coordX: Double(spotData.coordinates.x),
                        coordY: Double(spotData.coordinates.y),
                        coordZ: Double(spotData.coordinates.z),
                        bodyPart: spotData.bodyPart,
                        createdAt: Date()
                    )
                    location = try await supabase.createBodyLocation(newLocation)
                    bodyLocations.append(location)
                }
            }

            // Upload image
            let imageUrl = await uploadImage(spotData.image)
            
            guard !imageUrl.isEmpty else {
                errorMessage = "Failed to upload image"
                return
            }

            // Create spot
            let newSpot = BodySpot(
                id: UUID(),
                locationId: location.id,
                imageUrl: imageUrl,
                description: spotData.description,
                bodyPart: spotData.bodyPart,
                asymmetry: spotData.asymmetry,
                border: spotData.border,
                color: spotData.color,
                diameter: spotData.diameter,
                evolving: spotData.evolving,
                notes: spotData.notes,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase.createBodySpot(newSpot)
            bodySpots.append(newSpot)

        } catch {
            errorMessage = "Failed to save spot: \(error.localizedDescription)"
            print("❌ Error saving spot: \(error)")
        }
    }

    func deleteSpot(_ spot: BodySpot) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Delete from database
            try await supabase.deleteBodySpot(spot.id)
            
            // Delete image from storage
            if !spot.imageUrl.isEmpty {
                let fileName = spot.imageUrl.split(separator: "/").last.map(String.init) ?? ""
                if !fileName.isEmpty, let userId = userId {
                    try? await supabase.deleteImage(bucket: "body-scans", path: "\(userId.uuidString)/\(fileName)")
                }
            }
            
            // Remove from local state
            bodySpots.removeAll { $0.id == spot.id }
            
            // Check if location has no more spots and remove it
            let hasOtherSpots = bodySpots.contains { $0.locationId == spot.locationId }
            if !hasOtherSpots {
                bodyLocations.removeAll { $0.id == spot.locationId }
            }
            
            print("✅ Successfully deleted spot")
            
        } catch {
            errorMessage = "Failed to delete spot: \(error.localizedDescription)"
            print("❌ Error deleting spot: \(error)")
        }
    }

    // MARK: - Image Upload
    
    private func uploadImage(_ image: UIImage?) async -> String {
        guard let image = image,
              let imageData = image.jpegData(compressionQuality: 0.8),
              let userId = userId else {
            return ""
        }
        
        do {
            // Create unique filename
            let filename = "\(userId.uuidString)/\(UUID().uuidString).jpg"
            
            // Check if user is authenticated in Supabase
            let session = try? await supabase.client.auth.session
            guard session != nil else {
                errorMessage = "Not authenticated. Please sign out and sign in again."
                return ""
            }
            
            // Upload to Supabase Storage
            let uploadedFile = try await supabase.client.storage
                .from("body-scans")
                .upload(path: filename, file: imageData, options: .init(contentType: "image/jpeg"))
            
            // Get public URL
            let publicURL = try supabase.client.storage
                .from("body-scans")
                .getPublicURL(path: filename)
            
            return publicURL.absoluteString
        } catch {
            print("❌ Error uploading image: \(error)")
            
            // Provide more helpful error messages
            let errorString = "\(error)"
            if errorString.contains("403") || errorString.contains("Unauthorized") || errorString.contains("row-level security") {
                errorMessage = "⚠️ Storage permission denied. Please configure Supabase storage policies. See STORAGE_SETUP.md for instructions."
            } else {
                errorMessage = "Failed to upload image: \(error.localizedDescription)"
            }
            return ""
        }
    }
}

// MARK: - Spot Form Data
struct SpotFormData {
    var coordinates: SIMD3<Float>
    var location: BodyLocation?
    var image: UIImage?
    var bodyPart: String
    var description: String = ""
    var asymmetry: Bool = false
    var border: BorderType = .regular
    var color: ColorType = .uniform
    var diameter: Double = 2.0
    var evolving: EvolvingType = .unchanged
    var notes: String = ""
}
