import Foundation
import CoreLocation

// MARK: - Overpass Service
/// Service for fetching building data from OpenStreetMap via Overpass API
class OverpassService {
    static let shared = OverpassService()

    // Configuration
    private let overpassEndpoint = "https://overpass-api.de/api/interpreter"
    private let buildingRadiusMeters = 80
    private let overpassTimeoutSeconds = 25
    private let maxRetries = 2
    private let retryDelay: TimeInterval = 1.5

    // Cache management
    private let buildingCacheTTL: TimeInterval = 3600 // 1 hour
    private var buildingCache = [String: CachedBuildingEntry]()
    private var inflightRequests = [String: Task<[OverpassBuilding], Error>]()
    private let cacheQueue = DispatchQueue(label: "com.sunwize.overpass.cache", attributes: .concurrent)

    private init() {}

    // MARK: - Data Types

    struct OverpassBuilding: Codable {
        let id: String
        let points: [[Double]] // [lat, lon] pairs
        let tags: [String: String]
    }

    private struct CachedBuildingEntry: Codable {
        let buildings: [OverpassBuilding]
        let timestamp: Date
        var lastFailedAt: Date?
    }

    private struct OverpassResponse: Codable {
        let elements: [OverpassElement]
    }

    private struct OverpassElement: Codable {
        let id: Int
        let type: String
        let tags: [String: String]?
        let geometry: [Coordinate]?
        let members: [Member]?
    }

    private struct Coordinate: Codable {
        let lat: Double
        let lon: Double
    }

    private struct Member: Codable {
        let role: String
        let type: String
        let geometry: [Coordinate]?
    }

    // MARK: - Public API

    /// Fetch nearby buildings from OpenStreetMap
    func getNearbyBuildings(
        latitude: Double,
        longitude: Double,
        radius: Int? = nil
    ) async throws -> [OverpassBuilding] {
        let effectiveRadius = radius ?? buildingRadiusMeters
        let cacheKey = requestKey(lat: latitude, lon: longitude, radius: effectiveRadius)

        // Check cache
        if let cached = getCachedBuildings(for: cacheKey) {
            return cached
        }

        // Check if request is already in flight
        if let existing = inflightRequests[cacheKey] {
            return try await existing.value
        }

        // Create new request
        let task = Task<[OverpassBuilding], Error> {
            do {
                let buildings = try await performOverpassQuery(
                    latitude: latitude,
                    longitude: longitude,
                    radius: effectiveRadius
                )

                // Cache the result
                cacheQueue.async(flags: .barrier) {
                    self.buildingCache[cacheKey] = CachedBuildingEntry(
                        buildings: buildings,
                        timestamp: Date(),
                        lastFailedAt: nil
                    )
                }

                return buildings
            } catch {
                // Mark as failed
                cacheQueue.async(flags: .barrier) {
                    if var entry = self.buildingCache[cacheKey] {
                        entry.lastFailedAt = Date()
                        self.buildingCache[cacheKey] = entry
                    }
                }
                throw error
            }
        }

        inflightRequests[cacheKey] = task
        defer { inflightRequests.removeValue(forKey: cacheKey) }

        return try await task.value
    }

    /// Clear the building cache
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.buildingCache.removeAll()
        }
    }

    // MARK: - Private Methods

    private func requestKey(lat: Double, lon: Double, radius: Int) -> String {
        return "\(lat.rounded(toPlaces: 6)):\(lon.rounded(toPlaces: 6)):\(radius)"
    }

    private func getCachedBuildings(for key: String) -> [OverpassBuilding]? {
        return cacheQueue.sync {
            guard let entry = buildingCache[key] else { return nil }

            // Check if cache is still valid
            let age = Date().timeIntervalSince(entry.timestamp)
            if age > buildingCacheTTL {
                return nil
            }

            // Check if recently failed
            if let failedAt = entry.lastFailedAt {
                let failAge = Date().timeIntervalSince(failedAt)
                if failAge < 300 { // 5 minutes backoff
                    return entry.buildings // Return cached even if old
                }
            }

            return entry.buildings
        }
    }

    private func buildQuery(lat: Double, lon: Double, radius: Int) -> String {
        return """
        [out:json][timeout:\(overpassTimeoutSeconds)];
        (
          way["building"](around:\(radius),\(lat),\(lon));
          relation["building"](around:\(radius),\(lat),\(lon));
        );
        out geom;
        """
    }

    private func performOverpassQuery(
        latitude: Double,
        longitude: Double,
        radius: Int
    ) async throws -> [OverpassBuilding] {
        let query = buildQuery(lat: latitude, lon: longitude, radius: radius)
        let body = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        var request = URLRequest(url: URL(string: overpassEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = TimeInterval(overpassTimeoutSeconds)

        // Retry logic
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OverpassError.invalidResponse
                }

                if httpResponse.statusCode == 429 {
                    throw OverpassError.rateLimited
                }

                guard httpResponse.statusCode == 200 else {
                    throw OverpassError.httpError(statusCode: httpResponse.statusCode)
                }

                let overpassResponse = try JSONDecoder().decode(OverpassResponse.self, from: data)
                return parseElements(overpassResponse.elements)

            } catch {
                lastError = error
                print("[OverpassService] Request failed (attempt \(attempt)/\(maxRetries)): \(error)")

                if attempt < maxRetries {
                    let delay = retryDelay * Double(attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? OverpassError.unknownError
    }

    private func parseElements(_ elements: [OverpassElement]) -> [OverpassBuilding] {
        var buildings: [OverpassBuilding] = []

        for element in elements {
            if element.type == "way" {
                if let geometry = element.geometry, geometry.count >= 4 {
                    let points = normalizePoints(geometry)
                    buildings.append(OverpassBuilding(
                        id: "way:\(element.id)",
                        points: points,
                        tags: element.tags ?? [:]
                    ))
                }
            } else if element.type == "relation", let members = element.members {
                // Find outer boundary
                for member in members where member.role == "outer" {
                    if let geometry = member.geometry, geometry.count >= 4 {
                        let points = normalizePoints(geometry)
                        buildings.append(OverpassBuilding(
                            id: "relation:\(element.id)",
                            points: points,
                            tags: element.tags ?? [:]
                        ))
                        break
                    }
                }
            }
        }

        return buildings
    }

    private func normalizePoints(_ coordinates: [Coordinate]) -> [[Double]] {
        var points = coordinates.map { [$0.lat, $0.lon] }

        // Ensure polygon is closed
        if points.count > 2 {
            let first = points[0]
            let last = points[points.count - 1]
            if first[0] != last[0] || first[1] != last[1] {
                points.append(first)
            }
        }

        return points
    }
}

// MARK: - Errors

enum OverpassError: LocalizedError {
    case invalidResponse
    case rateLimited
    case httpError(statusCode: Int)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Overpass API"
        case .rateLimited:
            return "Rate limited by Overpass API"
        case .httpError(let code):
            return "HTTP error \(code) from Overpass API"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}

// MARK: - Extensions

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
