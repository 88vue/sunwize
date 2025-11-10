import SwiftUI

struct VitaminDTargetEditor: View {
    @State private var target: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) var dismiss

    init(currentTarget: Double, onSave: @escaping (Double) -> Void) {
        _target = State(initialValue: currentTarget)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60))
                        .foregroundColor(.yellow)

                    Text("Daily Vitamin D Target")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Set your personal daily goal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                // Current value display
                VStack(spacing: 8) {
                    Text("\(Int(target))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("International Units (IU)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Slider
                VStack(alignment: .leading, spacing: 16) {
                    Slider(
                        value: $target,
                        in: 100...20000,
                        step: 100
                    )
                    .accentColor(.yellow)

                    // Quick select buttons
                    HStack(spacing: 12) {
                        ForEach([400, 600, 1000, 2000, 4000], id: \.self) { value in
                            Button(action: {
                                withAnimation {
                                    target = Double(value)
                                }
                            }) {
                                Text("\(value)")
                                    .font(.caption)
                                    .fontWeight(Int(target) == value ? .bold : .regular)
                                    .foregroundColor(Int(target) == value ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Int(target) == value ? Color.yellow : Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Recommendations
                VStack(alignment: .leading, spacing: 12) {
                    Label("Recommended Daily Intake", systemImage: "info.circle")
                        .font(.headline)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Children (1-18 years):")
                                .font(.caption)
                            Spacer()
                            Text("600 IU")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Adults (19-70 years):")
                                .font(.caption)
                            Spacer()
                            Text("600-800 IU")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Older adults (70+ years):")
                                .font(.caption)
                            Spacer()
                            Text("800-1000 IU")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Maximum safe daily intake:")
                                .font(.caption)
                            Spacer()
                            Text("4000 IU")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)

                Spacer()

                // Save button
                Button(action: {
                    onSave(target)
                    dismiss()
                }) {
                    Text("Save Target")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Set Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}