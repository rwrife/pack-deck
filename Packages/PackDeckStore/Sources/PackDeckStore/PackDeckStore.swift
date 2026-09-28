import PackDeckKit

/// PackDeckStore persistence layer namespace.
///
/// M1 provides the package skeleton and wiring stub.
/// M3 implements GRDB schema, migrations, transactions, and backup codecs.
public enum PackDeckStore {
    /// Namespace identifier.
    public static let domain = "PackDeckStore"

    /// Current persistence schema milestone marker.
    public static let milestone = "M1-skeleton"
}
