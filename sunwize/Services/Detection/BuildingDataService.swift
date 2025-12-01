import Foundation
import CoreLocation

// MARK: - Building Data Service

/// Service for fetching and caching building polygon data from OpenStreetMap
/// Provides building proximity calculations and caching with spatial indexing
@MainActor
class BuildingDataService: ObservableObject {
    static let shared = BuildingDataService()

    // MARK: - Configuration

    struct Config {
        let cacheTTL: TimeInterval = 3600          // 1 hour cache
        let fetchRadius: Int = 150                  // 150m radius for API calls
        let geofenceRadius: Double = 30             // 30m radius for circular geofences
        let maxMonitoredRegions: Int = 20           // iOS limit for circular geofences
        let cacheGridPrecision: Int = 1000          // ~111m cache cells (3 decimal places)

        static let `default` = Config()
    }

    private let config: Config
    private let overpassService = OverpassService.shared

    // MARK: - Cache

    private var buildingCache: [String: BuildingCacheEntry] = [:]
    private var lastCachedLocation: CLLocationCoordinate2D?
    private var lastGeofenceSetupHash: Int = 0

    // MARK: - Monitored Regions

    /// Currently monitored building IDs for circular geofences
    private(set) var monitoredBuildings: Set<String> = []

    // MARK: - Persistence

    private lazy var persistenceDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BuildingDataService", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("BuildingDataService", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }()

    private lazy var buildingCacheURL = persistenceDirectory.appendingPathComponent("buildingCache.json")

    // MARK: - Data Types

    struct BuildingCacheEntry: Codable {
        let buildings: [OverpassService.OverpassBuilding]
        let timestamp: Date
    }

    // MARK: - Initialization

    private init(config: Config = .default) {
        self.config = config
        loadBuildingCache()
    }

    // MARK: - Public API

    /// Fetch nearby buildings, using cache when available
    func fetchNearbyBuildings(
        latitude: Double,
        longitude: Double
    ) async throws -> [OverpassBuilding] {
        let cacheKey = makeCacheKey(latitude: latitude, longitude: longitude)

        // Check cache first
        if let cached = buildingCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < config.cacheTTL {
            return cached.buildings
        }

        // Fetch from Overpass API
        let buildings = try await overpassService.getNearbyBuildings(
            latitude: latitude,
            longitude: longitude,
            radius: config.fetchRadius
        )

        // Cache the result
        buildingCache[cacheKey] = BuildingCacheEntry(
            buildings: buildings,
            timestamp: Date()
        )
        saveBuildingCache()

        return buildings
    }

    /// Get cached buildings for a location (returns nil if not cached)
    func getCachedBuildings(
        latitude: Double,
        longitude: Double
    ) -> [OverpassBuilding]? {
        let cacheKey = makeCacheKey(latitude: latitude, longitude: longitude)

        guard let cached = buildingCache[cacheKey],
              Date().timeIntervalSince(cached.timestamp) < config.cacheTTL else {
            return nil
        }

        return cached.buildings
    }

    /// Get the nearest building distance from cached data
    /// Returns nil if no cached building data available
    func getCachedNearestBuildingDistance(
        latitude: Double,
        longitude: Double
    ) -> Double? {
        let cacheKey = makeCacheKey(latitude: latitude, longitude: longitude)

        guard let cached = buildingCache[cacheKey],
              Date().timeIntervalSince(cached.timestamp) < config.cacheTTL,
              !cached.buildings.isEmpty else {
            return nil
        }

        let point = [latitude, longitude]
        let distance = GeometryUtils.nearestBuildingDistance(point: point, buildings: cached.buildings)

        // Filter out sentinel value for "no buildings found"
        return distance < 999999 ? distance : nil
    }

    /// Calculate nearest building distance from provided buildings
    func calculateNearestDistance(
        coordinate: CLLocationCoordinate2D,
        buildings: [OverpassBuilding]
    ) -> Double {
        guard !buildings.isEmpty else { return Double.infinity }

        let point = [coordinate.latitude, coordinate.longitude]
        let distance = GeometryUtils.nearestBuildingDistance(point: point, buildings: buildings)

        return distance < 999999 ? distance : Double.infinity
    }

    /// Check if coordinate is inside any building polygon
    func isInsideAnyBuilding(
        coordinate: CLLocationCoordinate2D,
        buildings: [OverpassBuilding]
    ) -> OverpassBuilding? {
        let point = [coordinate.latitude, coordinate.longitude]

        for building in buildings {
            if GeometryUtils.pointInPolygon(point: point, polygon: building.points) {
                return building
            }
        }

        return nil
    }

    // MARK: - Geofence Management

    /// Setup circular geofences around nearby buildings for background wake-up
    /// Returns the regions to monitor
    func setupBuildingGeofences(
        buildings: [OverpassBuilding],
        currentLocation: CLLocation,
        locationManager: CLLocationManager
    ) -> Set<CLCircularRegion> {
        // Skip if buildings haven't changed
        let buildingHash = buildings.prefix(config.maxMonitoredRegions).map { $0.id }.joined().hashValue
        if buildingHash == lastGeofenceSetupHash && !monitoredBuildings.isEmpty {
            return Set()
        }
        lastGeofenceSetupHash = buildingHash

        // Remove old geofences
        for region in locationManager.monitoredRegions {
            if monitoredBuildings.contains(region.identifier) {
                locationManager.stopMonitoring(for: region)
            }
        }
        monitoredBuildings.removeAll()

        // Sort buildings by distance and take nearest ones
        let sortedBuildings = buildings
            .compactMap { building -> (building: OverpassBuilding, distance: Double)? in
                guard let center = calculateBuildingCenter(building) else { return nil }
                let distance = currentLocation.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
                return (building, distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(config.maxMonitoredRegions)

        var regions: Set<CLCircularRegion> = []

        for (building, _) in sortedBuildings {
            guard let center = calculateBuildingCenter(building) else { continue }

            let region = CLCircularRegion(
                center: center,
                radius: config.geofenceRadius,
                identifier: building.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true

            locationManager.startMonitoring(for: region)
            monitoredBuildings.insert(building.id)
            regions.insert(region)
        }

        return regions
    }

    /// Calculate the center point of a building polygon
    func calculateBuildingCenter(_ building: OverpassBuilding) -> CLLocationCoordinate2D? {
        guard !building.points.isEmpty else { return nil }

        let latSum = building.points.reduce(0.0) { $0 + $1[0] }
        let lonSum = building.points.reduce(0.0) { $0 + $1[1] }
        let count = Double(building.points.count)

        return CLLocationCoordinate2D(
            latitude: latSum / count,
            longitude: lonSum / count
        )
    }

    /// Clear a specific building from monitored regions
    func stopMonitoringBuilding(
        buildingId: String,
        locationManager: CLLocationManager
    ) {
        for region in locationManager.monitoredRegions {
            if region.identifier == buildingId {
                locationManager.stopMonitoring(for: region)
            }
        }
        monitoredBuildings.remove(buildingId)
    }

    // MARK: - Cache Management

    /// Clear the entire building cache
    func clearCache() {
        buildingCache.removeAll()
        lastCachedLocation = nil
        lastGeofenceSetupHash = 0
        try? FileManager.default.removeItem(at: buildingCacheURL)
    }

    /// Prune expired cache entries
    func pruneExpiredCache() {
        let now = Date()
        let expiredKeys = buildingCache.filter { _, entry in
            now.timeIntervalSince(entry.timestamp) >= config.cacheTTL
        }.map { $0.key }

        for key in expiredKeys {
            buildingCache.removeValue(forKey: key)
        }

        if !expiredKeys.isEmpty {
            saveBuildingCache()
        }
    }

    // MARK: - Distance Zone Classification

    /// Classify distance to nearest building into zones
    func classifyDistanceZone(
        distance: Double,
        config: DetectionConfig = .default
    ) -> DistanceZone {
        if distance <= 0 {
            return .inside
        } else if distance < config.zoneProbablyInside {
            return .probablyInside
        } else if distance < config.zoneProbablyOutside {
            return .uncertain
        } else {
            return .probablyOutside
        }
    }

    enum DistanceZone {
        case inside           // 0m - inside polygon
        case probablyInside   // <10m
        case uncertain        // 10-40m
        case probablyOutside  // >40m
    }

    // MARK: - Private Helpers

    private func makeCacheKey(latitude: Double, longitude: Double) -> String {
        let latKey = Int(latitude * Double(config.cacheGridPrecision))
        let lonKey = Int(longitude * Double(config.cacheGridPrecision))
        return "\(latKey):\(lonKey)"
    }

    // MARK: - Persistence

    private func loadBuildingCache() {
        guard let data = try? Data(contentsOf: buildingCacheURL) else { return }
        let decoder = JSONDecoder()
        if let cache = try? decoder.decode([String: BuildingCacheEntry].self, from: data) {
            buildingCache = cache
            pruneExpiredCache()
        }
    }

    private func saveBuildingCache() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(buildingCache) else { return }
        try? data.write(to: buildingCacheURL, options: .atomic)
    }
}
