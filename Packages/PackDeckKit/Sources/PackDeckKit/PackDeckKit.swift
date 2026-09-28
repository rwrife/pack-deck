/// PackDeckKit — pure-domain core for Pack Deck.
///
/// Issue #1 ships only the skeleton namespace so CI has a real, testable
/// target. Issue #2 lands the kit, trip, item, recommendation, transition,
/// and summary entities plus deterministic recommendation rules here.
public enum PackDeckKit {
    /// Namespace marker for the domain layer.
    public static let domain = "PackDeckKit"

    /// Current build/CI milestone marker consumed by the app's debug surface.
    public static let milestone = "M1-skeleton"
}
