import SwiftUI

/// Reusable button component with multiple styles
struct PrimaryButton: View {
    // MARK: - Style Enum
    enum Style {
        case primary
        case secondary
        case destructive

        var backgroundColor: Color {
            switch self {
            case .primary:
                return .actionPrimary
            case .secondary:
                return .actionSecondary
            case .destructive:
                return .danger
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary, .destructive:
                return .white
            case .secondary:
                return Color(hex: "48484A")! // Gray-700
            }
        }
    }

    // MARK: - Properties
    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void

    @State private var isPressed = false

    // MARK: - Initialization
    init(
        title: String,
        icon: String? = nil,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    // MARK: - Body
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.UV.actionButtonHeight)
            .background(style.backgroundColor)
            .foregroundColor(style.foregroundColor)
            .cornerRadius(CornerRadius.base)
            .shadow(.medium)
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.buttonPress, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Preview
#Preview("Primary Button") {
    VStack(spacing: 20) {
        PrimaryButton(
            title: "Apply Sunscreen",
            icon: "sun.max",
            style: .primary
        ) {
            print("Primary tapped")
        }

        PrimaryButton(
            title: "I'm under cover!",
            icon: "umbrella.fill",
            style: .secondary
        ) {
            print("Secondary tapped")
        }

        PrimaryButton(
            title: "Delete Session",
            icon: "trash",
            style: .destructive
        ) {
            print("Destructive tapped")
        }

        HStack(spacing: 12) {
            PrimaryButton(
                title: "Cancel",
                style: .secondary
            ) {
                print("Cancel")
            }

            PrimaryButton(
                title: "Confirm",
                style: .primary
            ) {
                print("Confirm")
            }
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
