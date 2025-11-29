import SwiftUI
import Foundation

/// Centralized image loading utility for Body Spot images
/// Handles Supabase storage downloads with caching and loading states
@MainActor
class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var loadFailed = false

    private static let cache = NSCache<NSString, UIImage>()
    private var currentTask: Task<Void, Never>?

    init() {
        // Configure cache limits
        Self.cache.countLimit = 100 // Maximum 100 images
        Self.cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    /// Load an image from URL with caching
    /// - Parameter urlString: The image URL string
    func load(from urlString: String) {
        // Cancel any existing load task
        currentTask?.cancel()

        // Check cache first
        let cacheKey = urlString as NSString
        if let cachedImage = Self.cache.object(forKey: cacheKey) {
            self.image = cachedImage
            self.isLoading = false
            self.loadFailed = false
            return
        }

        // Start loading
        isLoading = true
        loadFailed = false

        currentTask = Task {
            do {
                let loadedImage = try await downloadImage(from: urlString)

                // Check if task was cancelled
                if Task.isCancelled { return }

                // Cache the image
                Self.cache.setObject(loadedImage, forKey: cacheKey)

                // Update state
                self.image = loadedImage
                self.isLoading = false
                self.loadFailed = false
            } catch {
                // Check if task was cancelled
                if Task.isCancelled { return }

                self.isLoading = false
                self.loadFailed = true
                print("❌ ImageLoader: Failed to load image - \(error.localizedDescription)")
            }
        }
    }

    /// Download image from Supabase storage or direct URL
    private func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw ImageLoaderError.invalidURL
        }

        // Try Supabase authenticated download first
        if let image = try? await downloadFromSupabase(url: url) {
            return image
        }

        // Fallback to direct URL download
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ImageLoaderError.invalidResponse
        }

        guard let image = UIImage(data: data) else {
            throw ImageLoaderError.invalidImageData
        }

        return image
    }

    /// Download image from Supabase storage bucket
    private func downloadFromSupabase(url: URL) async throws -> UIImage {
        let pathComponents = url.pathComponents

        guard let filePathIndex = pathComponents.firstIndex(of: "body-scans"),
              filePathIndex + 1 < pathComponents.count else {
            throw ImageLoaderError.invalidSupabasePath
        }

        let filePath = pathComponents[(filePathIndex + 1)...].joined(separator: "/")

        let data = try await SupabaseManager.shared.client.storage
            .from("body-scans")
            .download(path: filePath)

        guard let image = UIImage(data: data) else {
            throw ImageLoaderError.invalidImageData
        }

        return image
    }

    /// Cancel the current loading task
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    /// Clear the entire image cache
    static func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - Image Loader Errors
enum ImageLoaderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidImageData
    case invalidSupabasePath

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidImageData:
            return "Unable to decode image data"
        case .invalidSupabasePath:
            return "Invalid Supabase storage path"
        }
    }
}
