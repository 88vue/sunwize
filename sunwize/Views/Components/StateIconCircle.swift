import SwiftUI

/// Reusable icon circle component for state views
/// Replaces duplicate icon rendering code across OutsideStateView, InsideStateView, VehicleStateView, etc.
struct StateIconCircle: View {
    // MARK: - Properties
    let iconName: String
    var iconSize: CGFloat = 50
    var circleSize: CGFloat = 100
    var iconColor: Color = .orange
    var backgroundColor: Color = Color(.systemGroupedBackground)
    var topPadding: CGFloat = 32

    // MARK: - Body
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: circleSize, height: circleSize)

            Image(systemName: iconName)
                .font(.system(size: iconSize))
                .foregroundColor(iconColor)
        }
        .padding(.top, topPadding)
    }
}

// MARK: - Convenience Initializers

extension StateIconCircle {
    /// Create an outside state icon
    static var outside: StateIconCircle {
        StateIconCircle(
            iconName: UVStateIcon.outside,
            iconSize: 45,
            circleSize: 80,
            iconColor: .orange,
            topPadding: 24
        )
    }

    /// Create an inside state icon
    static var inside: StateIconCircle {
        StateIconCircle(
            iconName: UVStateIcon.inside,
            iconSize: 50,
            circleSize: 97,
            iconColor: .textSecondary,
            topPadding: 32
        )
    }

    /// Create a vehicle state icon
    static var vehicle: StateIconCircle {
        StateIconCircle(
            iconName: UVStateIcon.vehicle,
            iconSize: 55,
            circleSize: 100,
            iconColor: .blue,
            topPadding: 32
        )
    }

    /// Create a night time state icon
    static var nightTime: StateIconCircle {
        StateIconCircle(
            iconName: UVStateIcon.nightTime,
            iconSize: 60,
            circleSize: 100,
            iconColor: Color(hex: "5B84D4")!,
            topPadding: 32
        )
    }

    /// Create an unknown/calculating state icon
    static var unknown: StateIconCircle {
        StateIconCircle(
            iconName: UVStateIcon.unknown,
            iconSize: 55,
            circleSize: 100,
            iconColor: .textSecondary,
            backgroundColor: Color(.systemGroupedBackground).opacity(0.3),
            topPadding: 16
        )
    }

    /// Create a sun safe state icon
    static var sunSafe: StateIconCircle {
        StateIconCircle(
            iconName: UVStateIcon.sunSafe,
            iconSize: 36,
            circleSize: 100,
            iconColor: .actionPrimary,
            topPadding: 24
        )
    }
}

// MARK: - Preview
#Preview("State Icon Circles") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            VStack {
                StateIconCircle.outside
                Text("Outside").font(.caption)
            }
            VStack {
                StateIconCircle.inside
                Text("Inside").font(.caption)
            }
        }

        HStack(spacing: 20) {
            VStack {
                StateIconCircle.vehicle
                Text("Vehicle").font(.caption)
            }
            VStack {
                StateIconCircle.nightTime
                Text("Night").font(.caption)
            }
        }

        HStack(spacing: 20) {
            VStack {
                StateIconCircle.unknown
                Text("Unknown").font(.caption)
            }
            VStack {
                StateIconCircle.sunSafe
                Text("Sun Safe").font(.caption)
            }
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
