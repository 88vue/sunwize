import SwiftUI

struct UVHistoryView: View {
    let history: [UVHistoryDay]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("7-Day UV History")
                        .font(.headline)
                        .padding(.horizontal)

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(history) { day in
                            VStack(spacing: 8) {
                                Text(day.date, format: .dateTime.weekday(.abbreviated))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Circle()
                                    .fill(day.isSafe ? Color.green : Color.red)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text("\(day.date.day)")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    )

                                Text("\(String(format: "%.1f", day.totalSED)) SED")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Fill remaining days
                        ForEach(0..<(7 - history.count), id: \.self) { _ in
                            VStack(spacing: 8) {
                                Text("-")
                                    .font(.caption)
                                    .foregroundColor(.clear)

                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 40, height: 40)

                                Text("-")
                                    .font(.system(size: 10))
                                    .foregroundColor(.clear)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Statistics
                    VStack(spacing: 16) {
                        Text("Weekly Statistics")
                            .font(.headline)

                        HStack(spacing: 20) {
                            StatBox(
                                title: "Safe Days",
                                value: "\(history.filter { $0.isSafe }.count)",
                                color: .green
                            )

                            StatBox(
                                title: "Exceeded Days",
                                value: "\(history.filter { !$0.isSafe }.count)",
                                color: .red
                            )

                            StatBox(
                                title: "Avg. SED",
                                value: String(format: "%.1f", history.map { $0.totalSED }.reduce(0, +) / Double(max(history.count, 1))),
                                color: .orange
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Daily breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily Details")
                            .font(.headline)

                        ForEach(history) { day in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(day.date, format: .dateTime.weekday(.wide))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Text("\(day.sessionCount) sessions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(String(format: "%.1f", day.totalSED)) SED")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Image(systemName: day.isSafe ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(day.isSafe ? .green : .red)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("UV History")
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

struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// Helper extension for getting day of month
extension Date {
    var day: Int {
        Calendar.current.component(.day, from: self)
    }
}