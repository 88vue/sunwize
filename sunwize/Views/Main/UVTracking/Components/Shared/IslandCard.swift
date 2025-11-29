import SwiftUI

/// Reusable island/card container component used throughout UV Tracking
struct IslandCard<Content: View>: View {
    // MARK: - Properties
    let backgroundColor: Color
    let cornerRadius: CGFloat
    let shadowStyle: ShadowStyle
    let padding: CGFloat
    let content: () -> Content

    // MARK: - Initialization
    init(
        backgroundColor: Color = .white,
        cornerRadius: CGFloat = CornerRadius.xl,
        shadowStyle: ShadowStyle = .medium,
        padding: CGFloat = Spacing.UV.islandPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.shadowStyle = shadowStyle
        self.padding = padding
        self.content = content
    }

    // MARK: - Body
    var body: some View {
        content()
            .padding(padding)
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
            .shadow(shadowStyle)
    }
}

// MARK: - Preview
#Preview("Island Card") {
    VStack(spacing: 20) {
        IslandCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Island Card")
                    .font(.headline)
                Text("This is a reusable island container")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        IslandCard(backgroundColor: .uvOutsideBackground) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Colored Background")
                    .font(.headline)
            }
        }

        IslandCard(shadowStyle: .large) {
            Text("Large Shadow")
                .font(.title)
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
