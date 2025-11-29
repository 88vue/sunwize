import SwiftUI

// MARK: - Vitamin D Page
struct VitaminDPage: View {
    @ObservedObject var viewModel: UVTrackingViewModel
    @Binding var showingHistory: Bool
    @Binding var showingTargetEditor: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Daily Progress Island
                DailyProgressIsland(
                    current: viewModel.currentVitaminD,
                    target: viewModel.vitaminDTarget,
                    streak: viewModel.vitaminDStreak,
                    onStreakTap: {
                        withAnimation {
                            showingHistory = true
                        }
                    }
                )

                // Current Progress Island
                CurrentProgressIsland(
                    progress: viewModel.vitaminDProgress
                )

                // Edit Target Button
                EditTargetButton {
                    withAnimation {
                        showingTargetEditor = true
                    }
                }
                .padding(.top, 4)

                // Body Exposure Island
                BodyExposureIsland(
                    exposureFactor: $viewModel.bodyExposureFactor,
                    onChange: { newValue in
                        viewModel.updateBodyExposure(newValue)
                    }
                )
            }
            .padding(.horizontal, Spacing.base)
            .padding(.top, 95)
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Preview
#Preview("Vitamin D Page") {
    struct PreviewWrapper: View {
        @StateObject private var viewModel = UVTrackingViewModel()
        @State private var showingHistory = false
        @State private var showingTargetEditor = false

        var body: some View {
            ZStack {
                VitaminDPage(
                    viewModel: viewModel,
                    showingHistory: $showingHistory,
                    showingTargetEditor: $showingTargetEditor
                )

                // Simulated popups
                if showingHistory {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingHistory = false
                        }

                    VStack {
                        Spacer()
                        Text("History Popup Here")
                            .padding()
                            .background(Color.white)
                            .cornerRadius(24)
                    }
                    .transition(.move(edge: .bottom))
                }

                if showingTargetEditor {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingTargetEditor = false
                        }

                    VStack {
                        Spacer()
                        Text("Target Editor Popup Here")
                            .padding()
                            .background(Color.white)
                            .cornerRadius(24)
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
    }

    return PreviewWrapper()
}
