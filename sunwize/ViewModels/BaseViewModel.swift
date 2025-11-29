import Foundation
import Combine

/// Base ViewModel class with common functionality
/// Provides loading state, error handling, and Combine subscription management
/// Subclass this to reduce boilerplate in ViewModels
@MainActor
class BaseViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Loading state for async operations
    @Published var isLoading = false

    /// Current error message (nil if no error)
    @Published var errorMessage: String?

    /// Whether to show error UI
    @Published var showError = false

    // MARK: - Combine

    /// Cancellables for Combine subscriptions
    var cancellables = Set<AnyCancellable>()

    // MARK: - Error Handling

    /// Set an error message and show error UI
    /// - Parameter message: The error message to display
    func setError(_ message: String) {
        errorMessage = message
        showError = true
        print("❌ [ViewModel] \(message)")
    }

    /// Clear error state
    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Async Operations

    /// Execute an async operation with automatic loading state and error handling
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - onSuccess: Callback with the result on success
    ///   - errorContext: Context string for error messages (e.g., "load user data")
    func performAsync<T>(
        _ operation: () async throws -> T,
        onSuccess: ((T) -> Void)? = nil,
        errorContext: String = "perform operation"
    ) async {
        isLoading = true
        clearError()

        do {
            let result = try await operation()
            onSuccess?(result)
        } catch {
            setError("Failed to \(errorContext): \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Execute an async operation with automatic loading state and error handling
    /// Uses defer to ensure loading state is always reset
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - errorContext: Context string for error messages
    func performAsyncWithDefer(
        _ operation: () async throws -> Void,
        errorContext: String = "perform operation"
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            setError("Failed to \(errorContext): \(error.localizedDescription)")
        }
    }

    // MARK: - Subscription Helpers

    /// Subscribe to a publisher and store in cancellables
    /// - Parameters:
    ///   - publisher: The publisher to subscribe to
    ///   - receiveValue: Handler for received values
    func subscribe<P: Publisher>(
        to publisher: P,
        receiveValue: @escaping (P.Output) -> Void
    ) where P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: receiveValue)
            .store(in: &cancellables)
    }
}

// MARK: - Error Handler Utility

/// Centralized error handling for consistent error reporting
enum ErrorHandler {
    /// Handle an error with logging and optional callback
    /// - Parameters:
    ///   - error: The error to handle
    ///   - context: Context string describing the operation
    ///   - completion: Optional callback with formatted error message
    static func handle(
        _ error: Error,
        context: String,
        completion: ((String) -> Void)? = nil
    ) {
        let message = "Failed to \(context): \(error.localizedDescription)"
        print("❌ [\(context)] \(message)")
        completion?(message)
    }
}
