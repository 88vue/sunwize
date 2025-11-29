import SwiftUI

// MARK: - Rounded Corner Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Custom Transitions
extension AnyTransition {
    static var scaleInOut: AnyTransition {
        let insertion = AnyTransition.modifier(
            active: ScaleOpacityModifier(scale: 0.95, opacity: 0),
            identity: ScaleOpacityModifier(scale: 1, opacity: 1)
        )
        
        let removal = AnyTransition.modifier(
            active: ScaleOpacityModifier(scale: 0.95, opacity: 0),
            identity: ScaleOpacityModifier(scale: 1, opacity: 1)
        )
        
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

struct ScaleOpacityModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

// MARK: - Custom Animations
extension Animation {
    static var scaleInOutEase: Animation {
        Animation.timingCurve(0.36, 0.66, 0.4, 1, duration: 0.4)
    }
}
