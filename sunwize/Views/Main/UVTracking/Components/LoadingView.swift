import SwiftUI

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Detecting location...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
