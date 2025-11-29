import SwiftUI

struct ManualCoverTimer: View {
    let getRemainingTime: () -> TimeInterval?  // Closure to get current remaining time from source of truth
    let onClear: () -> Void

    @State private var currentTimeRemaining: TimeInterval = 0
    @State private var timer: Timer?

    init(remainingTime: TimeInterval, onClear: @escaping () -> Void) {
        // Legacy initializer for backward compatibility - converts to closure
        self.getRemainingTime = { remainingTime }
        self.onClear = onClear
    }

    init(getRemainingTime: @escaping () -> TimeInterval?, onClear: @escaping () -> Void) {
        // New initializer that accepts a closure to query the source of truth
        self.getRemainingTime = getRemainingTime
        self.onClear = onClear
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("UV tracking paused for")
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(timeRemainingText)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(currentTimeRemaining < 300 ? .orange : .purple)

            Text("You're marked as under cover")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Button(action: onClear) {
                Label("Resume Tracking", systemImage: "xmark.circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(Color.purple)
                    .cornerRadius(12)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.05))
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var timeRemainingText: String {
        let hours = Int(currentTimeRemaining) / 3600
        let minutes = Int(currentTimeRemaining) % 3600 / 60
        let seconds = Int(currentTimeRemaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func startTimer() {
        // Initialize from source of truth
        currentTimeRemaining = getRemainingTime() ?? 0

        // Timer that queries source of truth every second
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateTimeRemaining()
        }
    }

    private func updateTimeRemaining() {
        // Query the source of truth instead of counting down locally
        // This ensures UI stays in sync with LocationManager's actual expiration time
        if let remaining = getRemainingTime(), remaining > 0 {
            currentTimeRemaining = remaining
        } else {
            // Timer expired or override was cleared externally
            currentTimeRemaining = 0
            timer?.invalidate()
            timer = nil

            // Only call onClear if we actually hit zero (not if cleared externally)
            // Check again to prevent double-clearing
            if getRemainingTime() == nil || getRemainingTime()! <= 0 {
                onClear()
            }
        }
    }
}
