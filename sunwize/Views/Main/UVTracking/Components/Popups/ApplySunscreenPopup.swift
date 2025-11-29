import SwiftUI

/// Apply sunscreen popup for SPF selection
struct ApplySunscreenPopup: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let onConfirm: (Int, Date) -> Void

    @State private var selectedSPF: Int = 50
    @State private var applicationTime: Date = Date()

    private let spfOptions = [15, 30, 50]

    // MARK: - Body
    var body: some View {
        BottomSheetView(
            isPresented: $isPresented,
            title: "Apply Sunscreen",
            maxHeight: 450
        ) {
            VStack(spacing: 24) {
                        // Description
                        Text("Log your sunscreen application")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        // SPF Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SPF Level")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textSecondary)

                            HStack(spacing: 12) {
                                ForEach(spfOptions, id: \.self) { spf in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedSPF = spf
                                        }
                                    }) {
                                        Text("SPF \(spf)")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(selectedSPF == spf ? .white : .textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .background(selectedSPF == spf ? Color.orange : Color.slate50)
                                            .cornerRadius(CornerRadius.base)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        // Application Time
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Application Time")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textSecondary)

                            VStack(spacing: 0) {
                                // Time display
                                VStack(spacing: 8) {
                                    Text(formatTime(applicationTime))
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.textPrimary)

                                    Text("Now")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                            .background(Color.slate50)
                            .cornerRadius(CornerRadius.base)
                        }

                        // Action Buttons
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.bottomSheetPresent) {
                                    isPresented = false
                                }
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Layout.buttonHeight)
                                    .background(Color.slate200)
                                    .cornerRadius(CornerRadius.base)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                onConfirm(selectedSPF, applicationTime)
                                withAnimation(.bottomSheetPresent) {
                                    isPresented = false
                                }
                            }) {
                                Text("Confirm")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: Layout.buttonHeight)
                                    .background(Color.orange)
                                    .cornerRadius(CornerRadius.base)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, 110)
                }
        .onAppear {
            // Reset to defaults when shown
            applicationTime = Date()
            selectedSPF = 50
        }
    }

    // MARK: - Helper Methods
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview
#Preview("Apply Sunscreen Popup") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                Button("Show Sunscreen") {
                    isPresented = true
                }

                ApplySunscreenPopup(
                    isPresented: $isPresented,
                    onConfirm: { spf, time in
                        print("Applied SPF \(spf) at \(time)")
                    }
                )
            }
        }
    }

    return PreviewWrapper()
}
