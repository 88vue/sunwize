import SwiftUI

struct SunscreenTimer: View {
    let appliedTime: Date
    let onReapply: () -> Void
    let onExpire: (() -> Void)?

    @State private var timeRemaining: TimeInterval = 0
    @State private var timer: Timer?
    
    init(appliedTime: Date, onReapply: @escaping () -> Void, onExpire: (() -> Void)? = nil) {
        self.appliedTime = appliedTime
        self.onReapply = onReapply
        self.onExpire = onExpire
    }

    private var protectionDuration: TimeInterval {
        AppConfig.sunscreenProtectionDuration
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("You are sunsafe for the next")
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(timeRemainingText)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(timeRemaining < 600 ? .orange : .green)

            Text("Sunscreen applied at \(appliedTime, formatter: timeFormatter)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Button(action: onReapply) {
                Label("Reapply Sunscreen", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(timeRemaining <= 0 ? Color.orange : Color.blue)
                    .cornerRadius(12)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.05))
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var timeRemainingText: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) % 3600 / 60
        let seconds = Int(timeRemaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func startTimer() {
        updateTimeRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateTimeRemaining()
        }
    }

    private func updateTimeRemaining() {
        let elapsed = Date().timeIntervalSince(appliedTime)
        timeRemaining = max(0, protectionDuration - elapsed)

        if timeRemaining <= 0 {
            timer?.invalidate()
            timer = nil
            // Notify parent that sunscreen protection has expired
            onExpire?()
        }
    }
}

// MARK: - Formatters
private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
}()