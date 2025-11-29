import SwiftUI

/// Island containing the circular progress ring
struct CurrentProgressIsland: View {
    // MARK: - Properties
    let progress: Double // 0.0 to 1.0

    // MARK: - Body
    var body: some View {
        IslandCard {
            VitaminDProgressRing(progress: progress)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - Preview
#Preview("Current Progress Island") {
    VStack(spacing: 20) {
        CurrentProgressIsland(progress: 0.25)
        CurrentProgressIsland(progress: 0.5)
        CurrentProgressIsland(progress: 0.75)
        CurrentProgressIsland(progress: 1.0)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
