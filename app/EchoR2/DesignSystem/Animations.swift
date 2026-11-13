import SwiftUI
import UIKit

/// Motion tokens (DESIGN.md "Motion"). Springs everywhere; Reduce Motion swaps
/// every one of them for a short cross-fade.
enum Motion {
    /// Press states, chips, toggles, disclosure chevrons.
    static let snappy: Animation = .spring(response: 0.30, dampingFraction: 0.86)
    /// List insert / remove / reorder, the Other section.
    static let list: Animation = .spring(response: 0.42, dampingFraction: 0.84)
    /// Screen-level swaps: pairing to list, banners, loading/empty/error.
    static let gentle: Animation = .spring(response: 0.50, dampingFraction: 0.86)
    /// Reduce Motion fallback.
    static let fade: Animation = .easeInOut(duration: 0.2)

    /// `withAnimation` that honours Reduce Motion (for action closures).
    @MainActor static func animate(_ animation: Animation, _ body: () -> Void) {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? fade : animation, body)
    }
}

extension View {
    /// `.animation(_:value:)` that honours Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(accessibilityReduceMotion ? Motion.fade : animation, value: value)
    }
}

/// Soft press-down for any custom button. Use instead of drag-gesture press tracking,
/// which fights scroll views.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .motion(Motion.snappy, value: configuration.isPressed)
    }
}
