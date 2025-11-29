import SwiftUI

/// UV/Vitamin D toggle component with smooth sliding animation
struct UVToggle: View {
    // MARK: - Properties
    @Binding var selection: Int
    @Namespace private var animation

    private let options = ["UV Tracking", "Vitamin D"]

    // MARK: - Body
    var body: some View {
        let togglePadding = Spacing.UV.togglePadding
        let buttonHeight = Layout.UV.toggleHeight - (togglePadding * 2)
        let grayColor = Color(hex: "6E6C6C")!

        return HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.toggleSwipe) {
                        selection = index
                    }
                }) {
                    Text(options[index])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selection == index ? .black : grayColor)
                        .frame(width: Layout.UV.toggleButtonWidth, height: buttonHeight)
                        .background(toggleBackground(for: index))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(togglePadding)
        .frame(width: Layout.UV.toggleWidth, height: Layout.UV.toggleHeight)
        .background(Color.uvToggleBackground)
        .cornerRadius(40)
    }

    // MARK: - Helper Views
    @ViewBuilder
    private func toggleBackground(for index: Int) -> some View {
        if selection == index {
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.uvToggleSelected)
                .matchedGeometryEffect(id: "toggle", in: animation)
        }
    }
}

// MARK: - Preview
#Preview("UV Toggle") {
    struct PreviewWrapper: View {
        @State private var selection = 0

        var body: some View {
            VStack(spacing: 40) {
                UVToggle(selection: $selection)

                Text("Current selection: \(selection == 0 ? "UV Tracking" : "Vitamin D")")
                    .font(.headline)

                Button("Toggle") {
                    withAnimation {
                        selection = selection == 0 ? 1 : 0
                    }
                }
            }
            .padding()
            .background(Color.white)
        }
    }

    return PreviewWrapper()
}
