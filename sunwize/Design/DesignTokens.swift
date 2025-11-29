import SwiftUI

// MARK: - Spacing System (8pt Grid)
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 32
    static let xxxxl: CGFloat = 40

    // MARK: Bottom Sheet Specific Spacing
    enum BottomSheet {
        static let dragHandleTop: CGFloat = 16        // Reduced from 24
        static let dragHandleBottom: CGFloat = 16     // Reduced from 28
        static let headerBottom: CGFloat = 16         // Reduced from 24
        static let contentToButton: CGFloat = 16      // Reduced from 24
        static let buttonBottom: CGFloat = 24         // Safe area bottom spacing
    }
}

// MARK: - Corner Radius Scale
enum CornerRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 14
    static let base: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

// MARK: - Layout Constants
enum Layout {
    // Modal Dimensions
    static let modalWidth: CGFloat = 334
    static let modalImageHeight: CGFloat = 280
    static let modalContentHeight: CGFloat = 440
    static let modalTotalHeight: CGFloat = 720

    // Image Dimensions
    static let thumbnailSize: CGFloat = 100
    static let photoUploadHeight: CGFloat = 176

    // Form Elements
    static let buttonHeight: CGFloat = 56
    static let inputHeight: CGFloat = 36
    static let textEditorHeight: CGFloat = 106

    // Touch Targets (iOS HIG minimum)
    static let minTouchTarget: CGFloat = 44
    static let iconButtonSize: CGFloat = 32
    static let circleButtonSize: CGFloat = 38
    static let smallCircleButton: CGFloat = 34

    // Drag Handle
    static let dragHandleWidth: CGFloat = 48
    static let dragHandleHeight: CGFloat = 4

    // Timeline
    static let timelineHeight: CGFloat = 330
    static let timelineCardHeight: CGFloat = 140
}

// MARK: - Color Palette
extension Color {
    // MARK: Slate Colors
    static let slate50 = Color(hex: "F8FAFC")!
    static let slate200 = Color(hex: "CBD5E1")!
    static let slate300 = Color(hex: "CBD5E1")!
    static let slate400 = Color(hex: "94A3B8")!
    static let slate500 = Color(hex: "64748B")!
    static let slate600 = Color(hex: "475569")!
    static let slate700 = Color(hex: "334155")!
    static let slate800 = Color(hex: "1E293B")!
    static let slate900 = Color(hex: "0F172B")!

    // MARK: Secondary Text Colors
    static let textPrimary = Color(hex: "0F172B")!
    static let textSecondary = Color(hex: "62748E")!
    static let textTertiary = Color(hex: "90A1B9")!
    static let textMuted = Color(hex: "45556C")!

    // MARK: Amber Colors (Evolution Badge)
    static let amber50 = Color(hex: "FFFBEB")!
    static let amber100 = Color(hex: "FEF3C6")!
    static let amber600 = Color(hex: "E17100")!
    static let amber900 = Color(hex: "7B3306")!

    // MARK: Status Colors
    static let success = Color(hex: "00D492")!
    static let warning = Color.orange
    static let danger = Color.red

    // MARK: Background Colors
    static let cardBackground = Color(hex: "F8FAFC")!
    static let cardBorder = Color(hex: "F1F5F9")!
}

// MARK: - Typography Scale
enum Typography {
    // MARK: Font Sizes
    static let largeTitle: CGFloat = 34
    static let title: CGFloat = 28
    static let title2: CGFloat = 22
    static let title3: CGFloat = 20
    static let headline: CGFloat = 18
    static let body: CGFloat = 16
    static let callout: CGFloat = 15
    static let subheadline: CGFloat = 14
    static let footnote: CGFloat = 12
    static let caption: CGFloat = 11
    static let caption2: CGFloat = 10

    // MARK: Letter Spacing (Tracking)
    static let tight: CGFloat = -0.44
    static let normal: CGFloat = -0.31
    static let wide: CGFloat = 0.6
    static let wider: CGFloat = 0.62

    // MARK: Line Spacing
    static let defaultLineSpacing: CGFloat = 11
}

// MARK: - Shadow Styles
enum ShadowStyle {
    case small
    case medium
    case large
    case modal

    var color: Color {
        switch self {
        case .small: return Color.black.opacity(0.1)
        case .medium: return Color.black.opacity(0.15)
        case .large: return Color.black.opacity(0.2)
        case .modal: return Color.black.opacity(0.25)
        }
    }

    var radius: CGFloat {
        switch self {
        case .small: return 2
        case .medium: return 5
        case .large: return 10
        case .modal: return 25
        }
    }

    var x: CGFloat {
        return 0
    }

    var y: CGFloat {
        switch self {
        case .small: return 1
        case .medium: return -2
        case .large: return 5
        case .modal: return 25
        }
    }
}

// MARK: - View Extensions for Design Tokens
extension View {
    func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
