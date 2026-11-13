import UIKit

/// The single ingress for haptics (DESIGN.md "Haptics", D-12). Views call the
/// semantic statics only; the generator mapping lives here.
@MainActor
enum Haptics {
    /// Send a message, start a session.
    static func send() { impact(.medium) }
    /// A message or state update arrives.
    static func arrival() { impact(.light) }
    /// A session changes state.
    static func stateChange() { impact(.soft) }
    /// Pull to refresh.
    static func refresh() { impact(.rigid) }
    /// Toggle, disclosure, picker choice.
    static func toggle() { UISelectionFeedbackGenerator().selectionChanged() }
    /// A destructive confirm opens or fires.
    static func destructive() { notify(.warning) }
    /// Any failure shown to the user.
    static func failure() { notify(.error) }
    /// Pairing succeeded (also: any explicit success confirmation).
    static func paired() { notify(.success) }

    private static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: s).impactOccurred()
    }
    private static func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(t)
    }
}
