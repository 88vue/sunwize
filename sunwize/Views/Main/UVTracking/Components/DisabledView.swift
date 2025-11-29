import SwiftUI

// MARK: - Disabled View
struct DisabledView: View {
    let feature: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("\(feature) is disabled")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enable in Profile settings")
                .font(.headline)
                .foregroundColor(.orange)
        }
        .padding()
    }
}
