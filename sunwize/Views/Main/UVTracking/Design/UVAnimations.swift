import SwiftUI

// MARK: - UV-Specific Animations
extension Animation {
    /// Toggle switch animation
    static var toggleSwipe: Animation {
        .spring(response: 0.35, dampingFraction: 0.7)
    }

    /// State transition animation
    static var stateTransition: Animation {
        .easeInOut(duration: 0.3)
    }

    /// Island appearance animation
    static var islandAppear: Animation {
        .spring(response: 0.4, dampingFraction: 0.75)
    }

    /// Progress ring update animation
    static var progressUpdate: Animation {
        .easeInOut(duration: 0.5)
    }

    /// Bottom sheet presentation
    static var bottomSheetPresent: Animation {
        .spring(response: 0.45, dampingFraction: 0.85)
    }

    /// Fade animation for overlays
    static var overlayFade: Animation {
        .easeInOut(duration: 0.2)
    }

    /// Button press animation
    static var buttonPress: Animation {
        .spring(response: 0.3, dampingFraction: 0.6)
    }
}

// MARK: - Custom Transitions
extension AnyTransition {
    /// Island slide-in transition
    static var islandSlide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Bottom sheet slide-up transition
    static var bottomSheet: AnyTransition {
        .move(edge: .bottom)
    }

    /// State fade transition
    static var stateFade: AnyTransition {
        .opacity
    }
}

// MARK: - Animation Timing
enum AnimationTiming {
    static let quick: Double = 0.2
    static let normal: Double = 0.3
    static let slow: Double = 0.5
}
