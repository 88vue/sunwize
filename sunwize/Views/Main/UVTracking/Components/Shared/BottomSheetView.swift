import SwiftUI

/// Reusable bottom sheet component for popups
struct BottomSheetView<Content: View>: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let title: String
    let maxHeight: CGFloat
    let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isDragging = false

    private let dragThreshold: CGFloat = 100

    // MARK: - Initialization
    init(
        isPresented: Binding<Bool>,
        title: String,
        maxHeight: CGFloat = Layout.UV.bottomSheetMaxHeight,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.title = title
        self.maxHeight = maxHeight
        self.content = content
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 9999)
                .fill(Color(.systemGray3))
                .frame(width: Layout.dragHandleWidth, height: Layout.dragHandleHeight)
                .padding(.top, Spacing.BottomSheet.dragHandleTop)
                .padding(.bottom, Spacing.BottomSheet.dragHandleBottom)

            // Header
            HStack {
                Text(title)
                    .font(.system(size: Typography.title3, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    withAnimation(.bottomSheetPresent) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: UVStateIcon.close)
                        .font(.system(size: Typography.footnote, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: Layout.iconButtonSize, height: Layout.iconButtonSize)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.BottomSheet.headerBottom)

            // Content
            content()
        }
        .frame(maxHeight: maxHeight)
        .background(Color.white)
        .clipShape(RoundedCorner(radius: CornerRadius.xl, corners: [.topLeft, .topRight]))
        .offset(y: max(offset, 0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        isDragging = true
                        offset = value.translation.height
                    }
                }
                .onEnded { value in
                    isDragging = false
                    if value.translation.height > dragThreshold {
                        withAnimation(.bottomSheetPresent) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.bottomSheetPresent) {
                            offset = 0
                        }
                    }
                }
        )
        .onChange(of: isPresented) { newValue in
            if !newValue {
                offset = 0
            }
        }
    }
}

// MARK: - Preview
#Preview("Bottom Sheet") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack {
                    Text("Main Content")
                        .font(.largeTitle)

                    Button("Show Sheet") {
                        isPresented = true
                    }
                }

                if isPresented {
                    BottomSheetView(
                        isPresented: $isPresented,
                        title: "Bottom Sheet"
                    ) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("This is a reusable bottom sheet component")
                                .font(.body)

                            ForEach(0..<5) { index in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Section \(index + 1)")
                                        .font(.headline)
                                    Text("Content for section \(index + 1)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.slate50)
                                .cornerRadius(CornerRadius.base)
                            }
                        }
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}
