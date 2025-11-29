import Foundation
import CoreLocation

// MARK: - Weather Service
class WeatherService {
    static let shared = WeatherService()

    private let session = URLSession.shared
    private var cache: [String: (data: Any, timestamp: Date)] = [:]
    private let cacheDuration: TimeInterval = AppConfig.uvIndexCacheDuration
    
    // CRITICAL FIX: Add synchronization queue to prevent race conditions
    // The cache dictionary was being accessed from multiple threads simultaneously,
    // causing EXC_BAD_ACCESS crashes when writing to cache
    private let cacheQueue = DispatchQueue(label: "com.sunwize.weatherservice.cache", attributes: .concurrent)

    private init() {}

    // MARK: - UV Index API

    func getCurrentUVIndex(latitude: Double, longitude: Double) async throws -> Double {
        let cacheKey = "uv_\(latitude)_\(longitude)"

        // Check cache (thread-safe read)
        let cachedValue: (data: Any, timestamp: Date)? = cacheQueue.sync {
            return cache[cacheKey]
        }
        
        if let cached = cachedValue,
           Date().timeIntervalSince(cached.timestamp) < cacheDuration,
           let uvIndex = cached.data as? Double {
            return uvIndex
        }

        // Fetch from CurrentUVIndex.com API (no API key required)
        let uvIndex = try await fetchCurrentUVIndexFromAPI(latitude: latitude, longitude: longitude)
        
        // Update cache (thread-safe write)
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache[cacheKey] = (data: uvIndex, timestamp: Date())
        }
        
        return uvIndex
    }

    func getUVForecast(latitude: Double, longitude: Double) async throws -> [UVForecastData] {
        let cacheKey = "uvforecast_\(latitude)_\(longitude)"

        // Check cache (thread-safe read)
        let cachedValue: (data: Any, timestamp: Date)? = cacheQueue.sync {
            return cache[cacheKey]
        }

        if let cached = cachedValue,
           Date().timeIntervalSince(cached.timestamp) < cacheDuration,
           let forecast = cached.data as? [UVForecastData] {
            return forecast
        }

        // Fetch from CurrentUVIndex.com API
        let forecast = try await fetchUVForecastFromAPI(latitude: latitude, longitude: longitude)

        // Update cache (thread-safe write)
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache[cacheKey] = (data: forecast, timestamp: Date())
        }

        return forecast
    }

    /// Fetches both current UV index and forecast in a single API call
    /// Returns (currentUV, forecast) - more efficient than calling both separately
    func getUVDataWithForecast(latitude: Double, longitude: Double) async throws -> (currentUV: Double, forecast: [UVForecastData]) {
        let cacheKey = "uvdata_combined_\(latitude)_\(longitude)"

        // Check cache (thread-safe read)
        let cachedValue: (data: Any, timestamp: Date)? = cacheQueue.sync {
            return cache[cacheKey]
        }

        if let cached = cachedValue,
           Date().timeIntervalSince(cached.timestamp) < cacheDuration,
           let combinedData = cached.data as? (currentUV: Double, forecast: [UVForecastData]) {
            return combinedData
        }

        // Fetch from CurrentUVIndex.com API (single call returns both)
        let result = try await fetchUVDataCombinedFromAPI(latitude: latitude, longitude: longitude)

        // Update cache (thread-safe write)
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache[cacheKey] = (data: result, timestamp: Date())
        }

        return result
    }

    // MARK: - Sun Times API

    func getSunTimes(latitude: Double, longitude: Double, date: Date) async throws -> SunTimes? {
        let cacheKey = "suntimes_\(latitude)_\(longitude)_\(dateKey(date))"

        // Check cache (thread-safe read)
        let cachedValue: (data: Any, timestamp: Date)? = cacheQueue.sync {
            return cache[cacheKey]
        }
        
        if let cached = cachedValue,
           Date().timeIntervalSince(cached.timestamp) < AppConfig.sunTimesCacheDuration,
           let sunTimes = cached.data as? SunTimes {
            return sunTimes
        }

        // Fetch from SunriseSunset.io API
        let sunTimes = try await fetchSunTimesFromAPI(latitude: latitude, longitude: longitude, date: date)
        
        // Update cache (thread-safe write)
        // CRITICAL FIX: This was causing EXC_BAD_ACCESS due to simultaneous writes
        if let sunTimes = sunTimes {
            cacheQueue.async(flags: .barrier) { [weak self] in
                self?.cache[cacheKey] = (data: sunTimes, timestamp: Date())
            }
        }
        
        return sunTimes
    }

    // MARK: - Simulation Methods (Replace with actual API calls)

    private func simulateUVIndex() -> Double {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 6..<8:
            return Double.random(in: 1...2)
        case 8..<10:
            return Double.random(in: 2...4)
        case 10..<14:
            return Double.random(in: 5...8)
        case 14..<16:
            return Double.random(in: 3...5)
        case 16..<18:
            return Double.random(in: 1...3)
        default:
            return 0
        }
    }

    private func generateSimulatedForecast() -> [UVForecastData] {
        var forecast: [UVForecastData] = []
        let calendar = Calendar.current
        let now = Date()

        for hourOffset in 0..<24 {
            if let date = calendar.date(byAdding: .hour, value: hourOffset, to: now) {
                let hour = calendar.component(.hour, from: date)
                var uvIndex: Double = 0

                switch hour {
                case 6..<8:
                    uvIndex = Double.random(in: 1...2)
                case 8..<10:
                    uvIndex = Double.random(in: 2...4)
                case 10..<14:
                    uvIndex = Double.random(in: 5...8)
                case 14..<16:
                    uvIndex = Double.random(in: 3...5)
                case 16..<18:
                    uvIndex = Double.random(in: 1...3)
                default:
                    uvIndex = 0
                }

                forecast.append(UVForecastData(time: date, uvIndex: uvIndex))
            }
        }

        return forecast
    }

    private func generateSimulatedSunTimes() -> SunTimes {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())

        // Simulate sunrise at 6:30 AM
        components.hour = 6
        components.minute = 30
        let sunrise = calendar.date(from: components) ?? Date()

        // Simulate sunset at 7:30 PM
        components.hour = 19
        components.minute = 30
        let sunset = calendar.date(from: components) ?? Date()

        // Solar noon at 1:00 PM
        components.hour = 13
        components.minute = 0
        let solarNoon = calendar.date(from: components) ?? Date()

        let formatter = ISO8601DateFormatter()

        return SunTimes(
            sunrise: formatter.string(from: sunrise),
            sunset: formatter.string(from: sunset),
            solarNoon: formatter.string(from: solarNoon),
            dayLength: "13:00:00",
            civilTwilightBegin: formatter.string(from: sunrise.addingTimeInterval(-1800)),
            civilTwilightEnd: formatter.string(from: sunset.addingTimeInterval(1800))
        )
    }

    // MARK: - Helpers

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Actual API Implementation
extension WeatherService {
    // CurrentUVIndex.com API - No API key required
    private func fetchCurrentUVIndexFromAPI(latitude: Double, longitude: Double) async throws -> Double {
        let urlString = "\(AppConfig.currentUVIndexBaseURL)/uvi?latitude=\(latitude)&longitude=\(longitude)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // CurrentUVIndex.com returns: { ok, latitude, longitude, now: { time, uvi }, forecast: [...], history: [...] }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let now = json?["now"] as? [String: Any]
        let uvi = now?["uvi"] as? Double ?? 0
        
        return uvi
    }
    
    private func fetchUVForecastFromAPI(latitude: Double, longitude: Double) async throws -> [UVForecastData] {
        let urlString = "\(AppConfig.currentUVIndexBaseURL)/uvi?latitude=\(latitude)&longitude=\(longitude)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Parse CurrentUVIndex.com response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        var combined: [(date: String, uvi: Double)] = []
        
        // Add history if available
        if let history = json?["history"] as? [[String: Any]] {
            for item in history {
                if let time = item["time"] as? String ?? item["date"] as? String,
                   let uvi = item["uvi"] as? Double {
                    combined.append((date: time, uvi: uvi))
                }
            }
        }
        
        // Add current value
        if let now = json?["now"] as? [String: Any],
           let time = now["time"] as? String ?? now["date"] as? String,
           let uvi = now["uvi"] as? Double {
            combined.append((date: time, uvi: uvi))
        }
        
        // Add forecast
        if let forecast = json?["forecast"] as? [[String: Any]] {
            for item in forecast {
                if let time = item["time"] as? String ?? item["date"] as? String,
                   let uvi = item["uvi"] as? Double {
                    combined.append((date: time, uvi: uvi))
                }
            }
        }
        
        // Sort by time
        combined.sort { first, second in
            let formatter = ISO8601DateFormatter()
            guard let date1 = formatter.date(from: first.date),
                  let date2 = formatter.date(from: second.date) else {
                return false
            }
            return date1 < date2
        }
        
        // Convert to UVForecastData
        let formatter = ISO8601DateFormatter()
        return combined.compactMap { item in
            guard let date = formatter.date(from: item.date) else { return nil }
            return UVForecastData(time: date, uvIndex: item.uvi)
        }
    }

    /// Combined fetch that returns both current UV and forecast from single API call
    private func fetchUVDataCombinedFromAPI(latitude: Double, longitude: Double) async throws -> (currentUV: Double, forecast: [UVForecastData]) {
        let urlString = "\(AppConfig.currentUVIndexBaseURL)/uvi?latitude=\(latitude)&longitude=\(longitude)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Parse CurrentUVIndex.com response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Extract current UV from "now" field
        var currentUV: Double = 0.0
        if let now = json?["now"] as? [String: Any],
           let uvi = now["uvi"] as? Double {
            currentUV = uvi
        }

        // Build forecast array (history + now + forecast)
        var combined: [(date: String, uvi: Double)] = []

        // Add history if available
        if let history = json?["history"] as? [[String: Any]] {
            for item in history {
                if let time = item["time"] as? String ?? item["date"] as? String,
                   let uvi = item["uvi"] as? Double {
                    combined.append((date: time, uvi: uvi))
                }
            }
        }

        // Add current value
        if let now = json?["now"] as? [String: Any],
           let time = now["time"] as? String ?? now["date"] as? String,
           let uvi = now["uvi"] as? Double {
            combined.append((date: time, uvi: uvi))
        }

        // Add forecast
        if let forecast = json?["forecast"] as? [[String: Any]] {
            for item in forecast {
                if let time = item["time"] as? String ?? item["date"] as? String,
                   let uvi = item["uvi"] as? Double {
                    combined.append((date: time, uvi: uvi))
                }
            }
        }

        // Sort by time
        combined.sort { first, second in
            let formatter = ISO8601DateFormatter()
            guard let date1 = formatter.date(from: first.date),
                  let date2 = formatter.date(from: second.date) else {
                return false
            }
            return date1 < date2
        }

        // Convert to UVForecastData
        let formatter = ISO8601DateFormatter()
        let forecastData = combined.compactMap { item -> UVForecastData? in
            guard let date = formatter.date(from: item.date) else { return nil }
            return UVForecastData(time: date, uvIndex: item.uvi)
        }

        return (currentUV: currentUV, forecast: forecastData)
    }

    // SunriseSunset.io API
    private func fetchSunTimesFromAPI(latitude: Double, longitude: Double, date: Date) async throws -> SunTimes? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        // Get device timezone (like Expo implementation)
        let timezone = TimeZone.current.identifier

        let urlString = "\(AppConfig.sunriseSunsetBaseURL)?lat=\(latitude)&lng=\(longitude)&date=\(dateString)&timezone=\(timezone)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let sunResponse = try JSONDecoder().decode(SunTimesResponse.self, from: data)
        return sunResponse.status == "OK" ? sunResponse.results : nil
    }
}