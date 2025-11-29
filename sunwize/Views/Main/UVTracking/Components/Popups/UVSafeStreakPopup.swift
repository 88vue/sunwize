import SwiftUI

/// UV Safe Streak popup showing current streak and weekly history
struct UVSafeStreakPopup: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let currentStreak: Int
    let weeklyHistory: [(date: Date, isSafe: Bool)]

    // Get last 7 days
    private var last7Days: [(date: Date, isSafe: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let isSafe = weeklyHistory.first(where: {
                calendar.isDate($0.date, inSameDayAs: date)
            })?.isSafe ?? false
            return (date: date, isSafe: isSafe)
        }.reversed()
    }

    @State private var dragOffset: CGFloat = 0

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 9999)
                .fill(Color(.systemGray3))
                .frame(width: Layout.dragHandleWidth, height: Layout.dragHandleHeight)
                .padding(.top, Spacing.BottomSheet.dragHandleTop)
                .padding(.bottom, Spacing.BottomSheet.dragHandleBottom)

            // Header
            HStack(alignment: .top) {
                Text("UV Safe Streak")
                    .font(.system(size: Typography.title3, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: Typography.footnote, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: Layout.iconButtonSize, height: Layout.iconButtonSize)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.BottomSheet.headerBottom)

                VStack(spacing: 32) {
                    // Current streak display
                    VStack(spacing: 8) {
                        Text("Current Streak")
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.8))

                        Text("\(currentStreak)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)

                        Text("days protected")
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color.orange.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(CornerRadius.xl)

                    // This week section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("This Week")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textSecondary)

                        // Week grid
                        HStack(spacing: 0) {
                            ForEach(last7Days, id: \.date) { day in
                                DayCell(
                                    date: day.date,
                                    isSafe: day.isSafe,
                                    isToday: Calendar.current.isDateInToday(day.date)
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, 110)
        }
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(.medium)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation {
                            isPresented = false
                        }
                    } else {
                        withAnimation {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

// MARK: - Day Cell Component
struct DayCell: View {
    let date: Date
    let isSafe: Bool
    let isToday: Bool

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Status circle
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)

                if isSafe {
                    Image(systemName: UVStateIcon.checkmark)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else if Calendar.current.isDateInToday(date) {
                    // Empty for today if not yet safe
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textSecondary)
                } else {
                    Image(systemName: UVStateIcon.xmark)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Day name
            Text(dayName)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
    }

    private var backgroundColor: Color {
        if isSafe {
            return .actionPrimary
        } else if isToday {
            return .slate200
        } else {
            return Color(hex: "FF3B30")! // Red
        }
    }
}

// MARK: - Preview
#Preview("UV Safe Streak Popup") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                Button("Show Streak") {
                    isPresented = true
                }

                UVSafeStreakPopup(
                    isPresented: $isPresented,
                    currentStreak: 12,
                    weeklyHistory: [
                        (date: Date().addingTimeInterval(-6 * 86400), isSafe: true),
                        (date: Date().addingTimeInterval(-5 * 86400), isSafe: true),
                        (date: Date().addingTimeInterval(-4 * 86400), isSafe: true),
                        (date: Date().addingTimeInterval(-3 * 86400), isSafe: false),
                        (date: Date().addingTimeInterval(-2 * 86400), isSafe: true),
                        (date: Date().addingTimeInterval(-1 * 86400), isSafe: true),
                        (date: Date(), isSafe: true)
                    ]
                )
            }
        }
    }

    return PreviewWrapper()
}
