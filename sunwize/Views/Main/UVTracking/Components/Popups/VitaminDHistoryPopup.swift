import SwiftUI

/// Bottom sheet popup showing 7-day vitamin D history with interactive bar chart
struct VitaminDHistoryPopup: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let history: [VitaminDHistoryDay]
    let targetIU: Double

    @State private var selectedDay: VitaminDHistoryDay?

    // MARK: - Computed Properties
    private var sevenDayAverage: Double {
        guard !history.isEmpty else { return 0 }
        let total = history.prefix(7).reduce(0) { $0 + $1.totalIU }
        return total / Double(min(history.count, 7))
    }

    private var percentageOfGoal: Double {
        guard targetIU > 0 else { return 0 }
        return (sevenDayAverage / targetIU) * 100
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
                Text("Vitamin D History")
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


            VStack(spacing: 24) {
                // 7-Day Average Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("7-Day Average")
                        .font(.system(size: 14))
                        .foregroundColor(.white)

                    Text("\(formatNumber(sevenDayAverage)) IU")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    Text("\(Int(percentageOfGoal))% of daily goal")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 140)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.vitaminDPrimary, Color.vitaminDOrange]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.base)
                .clipped()

                // Bar Chart
                VitaminDBarChart(
                    history: Array(history.prefix(7)),
                    targetIU: targetIU,
                    selectedDay: $selectedDay
                )
                .clipped()

                // Selected day detail (if any)
                if let day = selectedDay {
                    SelectedDayDetail(day: day, targetIU: targetIU)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Helpers
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Bar Chart
struct VitaminDBarChart: View {
    let history: [VitaminDHistoryDay]
    let targetIU: Double
    @Binding var selectedDay: VitaminDHistoryDay?

    private let chartHeight: CGFloat = 140
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(spacing: 4) {
            // Chart area
            GeometryReader { geometry in
                let maxIU = max(history.map { $0.totalIU }.max() ?? targetIU, targetIU)
                let barWidth = (geometry.size.width - CGFloat((history.count - 1)) * 8) / CGFloat(history.count)

                ZStack(alignment: .bottom) {
                    // Target line
                    DottedLine()
                        .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(height: 1)
                        .offset(y: -chartHeight * CGFloat(targetIU / maxIU))

                    // Bars
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, day in
                            let barHeight = chartHeight * CGFloat(day.totalIU / maxIU)
                            let isSelected = selectedDay?.id == day.id

                            VStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(day.targetReached ? Color.vitaminDOrange : Color.gray.opacity(0.3))
                                    .frame(width: barWidth, height: max(barHeight, 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedDay = (selectedDay?.id == day.id) ? nil : day
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(height: chartHeight)
            }
            .frame(height: chartHeight)

            // Day labels
            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, day in
                    Text(dayLabels[getDayOfWeek(for: day.date)])
                        .font(.system(size: 10))
                        .foregroundColor(.slate500)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func getDayOfWeek(for date: Date) -> Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7 // Convert from Sunday=1 to Monday=0
    }
}

// MARK: - Dotted Line Shape
struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

// MARK: - Selected Day Detail
struct SelectedDayDetail: View {
    let day: VitaminDHistoryDay
    let targetIU: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(day.date))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)

                    Text("\(formatNumber(day.totalIU)) IU")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.vitaminDOrange)
                }

                Spacer()

                if day.targetReached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.vitaminDOrange)
                        .frame(width: geometry.size.width * CGFloat(min(day.totalIU / targetIU, 1.0)), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(Color.slate50)
        .cornerRadius(CornerRadius.base)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Preview
#Preview("Vitamin D History Popup") {
    struct PreviewWrapper: View {
        @State private var isPresented = true
        @State private var history: [VitaminDHistoryDay] = [
            VitaminDHistoryDay(date: Date().addingTimeInterval(-6 * 86400), totalIU: 800, targetReached: false),
            VitaminDHistoryDay(date: Date().addingTimeInterval(-5 * 86400), totalIU: 1600, targetReached: false),
            VitaminDHistoryDay(date: Date().addingTimeInterval(-4 * 86400), totalIU: 2200, targetReached: true),
            VitaminDHistoryDay(date: Date().addingTimeInterval(-3 * 86400), totalIU: 1200, targetReached: false),
            VitaminDHistoryDay(date: Date().addingTimeInterval(-2 * 86400), totalIU: 1400, targetReached: false),
            VitaminDHistoryDay(date: Date().addingTimeInterval(-1 * 86400), totalIU: 2400, targetReached: true),
            VitaminDHistoryDay(date: Date(), totalIU: 1500, targetReached: false)
        ]

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack {
                    Text("Vitamin D History")
                        .font(.largeTitle)

                    Button("Show Popup") {
                        isPresented = true
                    }
                }

                if isPresented {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isPresented = false
                        }

                    VStack {
                        Spacer()
                        VitaminDHistoryPopup(
                            isPresented: $isPresented,
                            history: history,
                            targetIU: 2000
                        )
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
    }

    return PreviewWrapper()
}
