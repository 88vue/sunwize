import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct VitaminDHistoryView: View {
    let history: [VitaminDHistoryDay]
    let targetIU: Double
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Weekly Vitamin D")
                        .font(.headline)
                        .padding(.horizontal)

                    // Bar chart
                    if !history.isEmpty {
                        #if canImport(Charts)
                        if #available(iOS 16.0, *) {
                            Chart(history) { day in
                                BarMark(
                                    x: .value("Day", day.date, unit: .day),
                                    y: .value("IU", day.totalIU)
                                )
                                .foregroundStyle(day.targetReached ? Color.green : Color.yellow)
                                .cornerRadius(4)

                                // Target line
                                RuleMark(y: .value("Target", targetIU))
                                    .foregroundStyle(Color.orange)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            }
                            .frame(height: 200)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day)) { value in
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel {
                                            Text(date, format: .dateTime.weekday(.abbreviated))
                                        }
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisValueLabel {
                                        if let iu = value.as(Double.self) {
                                            Text("\(Int(iu))")
                                        }
                                    }
                                    AxisGridLine()
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            SimpleVitaminDChart(history: history, targetIU: targetIU)
                                .frame(height: 200)
                                .padding(.horizontal)
                        }
                        #else
                        SimpleVitaminDChart(history: history, targetIU: targetIU)
                            .frame(height: 200)
                            .padding(.horizontal)
                        #endif
                    } else {
                        Text("No history available")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }

                    // Weekly summary
                    VStack(spacing: 16) {
                        Text("Weekly Summary")
                            .font(.headline)

                        HStack(spacing: 20) {
                            StatBox(
                                title: "Days Met",
                                value: "\(history.filter { $0.targetReached }.count)",
                                color: .green
                            )

                            StatBox(
                                title: "Total IU",
                                value: "\(Int(history.map { $0.totalIU }.reduce(0, +)))",
                                color: .yellow
                            )

                            StatBox(
                                title: "Avg. Daily",
                                value: "\(Int(history.map { $0.totalIU }.reduce(0, +) / Double(max(history.count, 1))))",
                                color: .orange
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Daily breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily Breakdown")
                            .font(.headline)

                        ForEach(history) { day in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(day.date, format: .dateTime.weekday(.wide))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    HStack(spacing: 4) {
                                        ProgressView(value: min(day.totalIU / targetIU, 1.0))
                                            .progressViewStyle(LinearProgressViewStyle(tint: day.targetReached ? .green : .yellow))
                                            .frame(width: 100)

                                        Text("\(Int(min(day.totalIU / targetIU * 100, 100)))%")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(Int(day.totalIU)) IU")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    if day.targetReached {
                                        Label("Target Met", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    // Information
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Vitamin D Information", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Text("The recommended daily intake of Vitamin D is 600 IU for most adults. Sunlight exposure is the best natural source, but supplements may be needed in winter months.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vitamin D History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Simple bar chart fallback for iOS 15
struct SimpleVitaminDChart: View {
    let history: [VitaminDHistoryDay]
    let targetIU: Double

    var maxIU: Double {
        max(history.map { $0.totalIU }.max() ?? targetIU, targetIU)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: geometry.size.width / CGFloat(history.count * 3)) {
                ForEach(history) { day in
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(day.targetReached ? Color.green : Color.yellow)
                            .frame(width: geometry.size.width / CGFloat(history.count * 2),
                                   height: geometry.size.height * CGFloat(day.totalIU / maxIU))
                            .cornerRadius(4)
                    }
                }
            }
            .overlay(
                // Target line
                GeometryReader { geo in
                    Path { path in
                        let y = geo.size.height * (1 - targetIU / maxIU)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            )
        }
    }
}