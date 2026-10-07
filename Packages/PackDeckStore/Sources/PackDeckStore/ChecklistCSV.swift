import Foundation

/// Offline, UTF-8 checklist export (issue #6).
///
/// Contract:
/// - Header: trip name, item name, kit source, recommended quantity, status.
/// - One row per trip item; every cell is quoted so commas/newlines survive.
/// - Cells whose first non-space character could be interpreted as a
///   spreadsheet formula get a leading `'` before sharing.
/// - Pure in-memory `Data` codec — zero network by construction.
public enum ChecklistCSV {
    public static let header = ["Trip name", "Item name", "Kit source", "Recommended quantity", "Status"]

    public static func encode(_ snapshot: PackDeckSnapshot) -> Data {
        var kits: [UUID: String] = [:]
        for kit in snapshot.kits { kits[kit.id] = kit.name }
        var trips: [UUID: String] = [:]
        for trip in snapshot.trips { trips[trip.id] = trip.name }

        var rows = [header.map(field).joined(separator: ",")]
        for item in snapshot.tripItems {
            let source: String
            if let kitID = item.sourceKitID {
                source = kits[kitID] ?? "Deleted kit"
            } else {
                source = "Ad-hoc"
            }
            rows.append([
                trips[item.tripID] ?? "Unknown trip",
                item.name,
                source,
                String(item.recommendation.quantity),
                snapshot.currentStatus(for: item.id).rawValue,
            ].map(field).joined(separator: ","))
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// RFC 4180 quoting plus formula-prefix neutralization (OWASP CSV
    /// injection): a shared file must never execute formulas on open.
    static func field(_ text: String) -> String {
        let guardFormula = text.first(where: { !$0.isWhitespace }).map { "=+-@".contains($0) } ?? false
        let escaped = guardFormula ? "'" + text : text
        return "\"" + escaped.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
