import Foundation
import CoreLocation

// MARK: - Geometry Utilities

struct GeometryUtils {

    /// Calculate haversine distance between two points in meters
    static func haversineDistance(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double
    ) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLat = (lat2 - lat1) * .pi / 180
        let deltaLon = (lon2 - lon1) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return R * c
    }

    /// Check if a point is inside a polygon using ray casting algorithm
    static func pointInPolygon(
        point: [Double],
        polygon: [[Double]]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }

        let lat = point[0]
        let lon = point[1]
        var inside = false

        var p1 = polygon[0]
        for i in 1...polygon.count {
            let p2 = polygon[i % polygon.count]

            if lon > min(p1[1], p2[1]) {
                if lon <= max(p1[1], p2[1]) {
                    if lat <= max(p1[0], p2[0]) {
                        let xIntersection = (lon - p1[1]) * (p2[0] - p1[0]) / (p2[1] - p1[1]) + p1[0]
                        if p1[0] == p2[0] || lat <= xIntersection {
                            inside.toggle()
                        }
                    }
                }
            }
            p1 = p2
        }

        return inside
    }

    /// Check if a point is inside any of the given polygons
    static func pointInAnyPolygon(
        point: [Double],
        polygons: [[[Double]]]
    ) -> Bool {
        for polygon in polygons {
            if pointInPolygon(point: point, polygon: polygon) {
                return true
            }
        }
        return false
    }

    /// Calculate the minimum distance from a point to a line segment
    static func distanceToLineSegment(
        point: [Double],
        lineStart: [Double],
        lineEnd: [Double]
    ) -> Double {
        let px = point[0]
        let py = point[1]
        let x1 = lineStart[0]
        let y1 = lineStart[1]
        let x2 = lineEnd[0]
        let y2 = lineEnd[1]

        let A = px - x1
        let B = py - y1
        let C = x2 - x1
        let D = y2 - y1

        let dot = A * C + B * D
        let lenSq = C * C + D * D

        var param = -1.0
        if lenSq != 0 {
            param = dot / lenSq
        }

        var xx: Double
        var yy: Double

        if param < 0 {
            xx = x1
            yy = y1
        } else if param > 1 {
            xx = x2
            yy = y2
        } else {
            xx = x1 + param * C
            yy = y1 + param * D
        }

        return haversineDistance(lat1: px, lon1: py, lat2: xx, lon2: yy)
    }

    /// Calculate the minimum distance from a point to a polygon boundary
    static func distanceToPolygon(
        point: [Double],
        polygon: [[Double]]
    ) -> Double {
        guard polygon.count >= 2 else { return Double.infinity }

        var minDistance = Double.infinity

        for i in 0..<polygon.count - 1 {
            let distance = distanceToLineSegment(
                point: point,
                lineStart: polygon[i],
                lineEnd: polygon[i + 1]
            )
            minDistance = min(minDistance, distance)
        }

        // Check closing edge if polygon is closed
        if polygon.count > 2 {
            let distance = distanceToLineSegment(
                point: point,
                lineStart: polygon[polygon.count - 1],
                lineEnd: polygon[0]
            )
            minDistance = min(minDistance, distance)
        }

        return minDistance
    }

    /// Find the nearest distance to any building polygon
    static func nearestBuildingDistance(
        point: [Double],
        buildings: [OverpassService.OverpassBuilding]
    ) -> Double {
        var minDistance = Double.infinity

        for building in buildings {
            guard building.points.count >= 3 else { continue }

            // If point is inside this building, distance is 0
            if pointInPolygon(point: point, polygon: building.points) {
                return 0
            }

            // Calculate distance to building boundary
            let distance = distanceToPolygon(point: point, polygon: building.points)
            minDistance = min(minDistance, distance)
        }

        return minDistance == Double.infinity ? 999999 : minDistance
    }

    /// Calculate the area of a polygon in square meters
    static func polygonArea(polygon: [[Double]]) -> Double {
        guard polygon.count >= 3 else { return 0 }

        var area = 0.0
        let n = polygon.count

        // Convert to projected coordinates (simple Mercator)
        let avgLat = polygon.reduce(0.0) { $0 + $1[0] } / Double(n)
        let cosLat = cos(avgLat * .pi / 180)

        for i in 0..<n {
            let j = (i + 1) % n
            let x1 = polygon[i][1] * cosLat * 111319.9 // Convert lon to meters
            let y1 = polygon[i][0] * 111319.9 // Convert lat to meters
            let x2 = polygon[j][1] * cosLat * 111319.9
            let y2 = polygon[j][0] * 111319.9

            area += x1 * y2 - x2 * y1
        }

        return abs(area) / 2.0
    }

    /// Check if a point is within a certain distance of any building
    static func isNearBuilding(
        point: [Double],
        buildings: [OverpassService.OverpassBuilding],
        threshold: Double
    ) -> Bool {
        let distance = nearestBuildingDistance(point: point, buildings: buildings)
        return distance <= threshold
    }
}