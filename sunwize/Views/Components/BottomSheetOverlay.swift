import SwiftUI

/// Reusable bottom sheet overlay component
/// Provides a consistent popup experience with background dimming and slide-up animation
/// Used throughout the app for modals that slide up from the bottom
struct BottomSheetOverlay<Content: View>: View {
    // MARK: - Properties
    let isPresented: Bool
    let onDismiss: () -> Void
    let content: Content

    // MARK: - Initialization
    init(
        isPresented: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.onDismiss = onDismiss
        self.content = content()
    }

    // MARK: - Body
    var body: some View {
        Group {
            if isPresented {
                // Background overlay
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }
                    .transition(.opacity)
                    .zIndex(2)

                // Content card
                VStack {
                    Spacer()
                    content
                }
                .transition(.move(edge: .bottom))
                .edgesIgnoringSafeArea(.bottom)
                .zIndex(3)
            }
        }
    }
}
