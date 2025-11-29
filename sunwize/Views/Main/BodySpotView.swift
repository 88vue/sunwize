import SwiftUI
import SceneKit

struct BodySpotView: View {
    @ObservedObject var viewModel: BodySpotViewModel
    @ObservedObject var uiState: BodySpotUIState
    @State private var isModelLoading = true

    var body: some View {
        ZStack {
            // Main content
            ZStack {
                // 3D Model Background
                BodyModel3DView(
                    spotMarkers: viewModel.spotMarkers,
                    isInteractive: true,
                    onModelTap: handleModelTap,
                    onSpotTap: handleSpotTap,
                    isLoading: $isModelLoading
                )
                .ignoresSafeArea()

                // UI Overlay
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Body Spot Tracker")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("\(viewModel.bodySpots.count) spots tracked")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "figure.stand")
                            .font(.title)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.base)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(.systemGroupedBackground).opacity(0.9),
                                Color(.systemGroupedBackground).opacity(0.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Spacer()

                    // Loading overlay
                    if isModelLoading {
                        VStack(spacing: Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading 3D Model...")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.9))
                    }

                    // Instructions
                    if !isModelLoading {
                        VStack {
                            Text("Double tap to add a new spot or zoom and tap orange dots to view existing spots")
                                .font(.callout)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(Spacing.base)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(CornerRadius.sm)
                                .padding(Spacing.base)
                                .padding(.bottom, Spacing.lg)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            Task {
                await viewModel.loadBodySpots()
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }

    }

    // MARK: - Helper Functions

    private func handleModelTap(_ coordinates: SIMD3<Float>) {
        uiState.selectedLocation = viewModel.handleModelTap(at: coordinates)
        withAnimation {
            uiState.bottomViewMode = .form
        }
    }

    private func handleSpotTap(_ locationId: String) {
        if let locationData = viewModel.handleSpotTap(locationId: locationId) {
            uiState.selectedLocation = locationData
            withAnimation {
                uiState.bottomViewMode = .timeline
            }
        }
    }
}

// MARK: - Clear Background View Helper
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
