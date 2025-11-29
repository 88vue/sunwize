import Foundation

/// Centralized date formatting utilities for consistent date display across the app
enum DateFormatters {
    // MARK: - Shared Formatters

    /// Format: "MMM d" (e.g., "Jan 15")
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Format: "MMM d, yyyy" (e.g., "Jan 15, 2024")
    static let monthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Format: "h:mm a" (e.g., "2:30 PM") - Used for short time display
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    /// Format: "MMM d, h:mm a" (e.g., "Jan 15, 2:30 PM")
    static let monthDayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    // MARK: - Convenience Methods

    /// Format a date as "MMM d" (e.g., "Jan 15")
    static func formatMonthDay(_ date: Date) -> String {
        return monthDay.string(from: date)
    }

    /// Format a date as "MMM d, yyyy" (e.g., "Jan 15, 2024")
    static func formatMonthDayYear(_ date: Date) -> String {
        return monthDayYear.string(from: date)
    }

    /// Format time interval in human-readable format with seconds support
    /// Examples: "45s", "2m 30s", "1h 15m"
    static func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
    }
}

// MARK: - Date Extension for Time Formatting

extension Date {
    /// Format date as short time (e.g., "2:30 PM")
    /// Replaces duplicate `formatTime()` methods across views
    func formattedTime() -> String {
        return DateFormatters.shortTime.string(from: self)
    }
}

// MARK: - Double Extension for Number Formatting

extension Double {
    /// Format as IU value with thousands separator (e.g., "1,500")
    /// Replaces duplicate `formatNumber()` methods across views
    func formattedAsIU() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: self)) ?? "\(Int(self))"
    }
}

extension Int {
    /// Format as IU value with thousands separator (e.g., "1,500")
    func formattedAsIU() -> String {
        return Double(self).formattedAsIU()
    }
}
