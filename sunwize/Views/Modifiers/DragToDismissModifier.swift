import SwiftUI

/// ViewModifier for drag-to-dismiss gesture on bottom sheets
/// Replaces duplicate drag gesture code across popup views
struct DragToDismissModifier: ViewModifier {
    // MARK: - Properties
    @Binding var isPresented: Bool
    var dismissThreshold: CGFloat = 100
    var onDismiss: (() -> Void)?

    @State private var dragOffset: CGFloat = 0

    // MARK: - Body
    func body(content: Content) -> some View {
        content
            .offset(y: max(dragOffset, 0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            withAnimation {
                                isPresented = false
                                onDismiss?()
                            }
                        } else {
                            withAnimation {
                                dragOffset = 0
                            }
                        }
                    }
            )
    }
}

// MARK: - View Extension
extension View {
    /// Add drag-to-dismiss gesture to a view
    /// - Parameters:
    ///   - isPresented: Binding to control presentation
    ///   - threshold: Distance to drag before dismissing (default: 100)
    ///   - onDismiss: Optional callback when dismissed
    func dragToDismiss(
        _ isPresented: Binding<Bool>,
        threshold: CGFloat = 100,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(DragToDismissModifier(
            isPresented: isPresented,
            dismissThreshold: threshold,
            onDismiss: onDismiss
        ))
    }
}

// MARK: - Preview
#Preview("Drag to Dismiss") {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            ZStack {
                Color.gray.opacity(0.3)
                    .ignoresSafeArea()

                if isPresented {
                    VStack {
                        Spacer()

                        VStack {
                            RoundedRectangle(cornerRadius: 9999)
                                .fill(Color(.systemGray3))
                                .frame(width: 40, height: 4)
                                .padding(.top, 8)

                            Text("Drag down to dismiss")
                                .padding()

                            Spacer()
                        }
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .dragToDismiss($isPresented)
                    }
                }

                if !isPresented {
                    Button("Show Sheet") {
                        isPresented = true
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}
