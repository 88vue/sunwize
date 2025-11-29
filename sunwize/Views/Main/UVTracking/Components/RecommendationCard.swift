import SwiftUI

// MARK: - Recommendation Card
struct RecommendationCard: View {
    let text: String
    let color: Color

    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding()
        .background(color)
        .cornerRadius(12)
    }
}
