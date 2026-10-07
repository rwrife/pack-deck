import Foundation
import PackDeckKit

/// Versioned JSON backup/restore codec for PackDeckStore (issue #3).
///
/// Format contract:
/// - `formatVersion` is an integer checked on import; unknown future
///   versions are rejected (`BackupError.unsupportedFormatVersion`) and
///   unknown past versions are never guessed at.
/// - The payload is the domain `PackDeckDataset`, which itself replay-
///   validates its transition ledger on decode — so a restored dataset is
///   always state-machine consistent.
/// - Zero network: pure in-memory `Data` <-> bytes codec.
public enum BackupCodec {
    /// Current backup format version emitted by `encode`.
    /// v2: timestamps carry floating-point seconds (v1 truncated to whole
    /// seconds, which lost ordering precision for rapid ledger events).
    public static let currentFormatVersion: Int = 2

    /// Backup format versions this build can read.
    public static let supportedFormatVersions: Set<Int> = [1, 2]

    /// v1 used ISO8601 with second precision. v2 stores dates as a
    /// floating-point seconds-since-epoch value, matching SQLite exactly.
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { source in
            let container = try source.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                guard timestamp.isFinite else {
                    throw BackupError.malformedBackup("non-finite timestamp")
                }
                return Date(timeIntervalSince1970: timestamp)
            }
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: string) else {
                throw BackupError.malformedBackup("unreadable timestamp")
            }
            return date
        }
        return decoder
    }

    public enum BackupError: Error, Equatable, Sendable {
        /// The backup carries a format version this build cannot read.
        case unsupportedFormatVersion(Int)
        /// The JSON envelope decoded but violated the backup contract.
        case malformedBackup(String)
    }

    /// JSON envelope: format version + dataset payload.
    struct Envelope: Codable {
        let formatVersion: Int
        let dataset: PackDeckDataset
    }

    /// Encodes a store snapshot into a stable, pretty-printed JSON backup.
    public static func encode(_ snapshot: PackDeckSnapshot) throws -> Data {
        try encode(snapshot.dataset)
    }

    public static func encode(_ dataset: PackDeckDataset) throws -> Data {
        let envelope = Envelope(formatVersion: currentFormatVersion, dataset: dataset)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(envelope)
    }

    public static func validateRelationalIntegrity(_ dataset: PackDeckDataset) throws {
        let kitIDs = Set(dataset.kits.map(\.id))
        guard kitIDs.count == dataset.kits.count else {
            throw BackupError.malformedBackup("duplicate kit id")
        }
        let kitItems = dataset.kits.flatMap(\.items)
        guard Set(kitItems.map(\.id)).count == kitItems.count else {
            throw BackupError.malformedBackup("duplicate kit item id")
        }
        let tripIDs = Set(dataset.trips.map(\.id))
        guard tripIDs.count == dataset.trips.count else {
            throw BackupError.malformedBackup("duplicate trip id")
        }
        let tripItemIDs = Set(dataset.tripItems.map(\.id))
        guard tripItemIDs.count == dataset.tripItems.count else {
            throw BackupError.malformedBackup("duplicate trip item id")
        }
        for item in dataset.tripItems {
            guard tripIDs.contains(item.tripID) else {
                throw BackupError.malformedBackup("trip item \(item.id) references missing trip \(item.tripID)")
            }
        }
        let transitionIDs = Set(dataset.transitions.map(\.id))
        guard transitionIDs.count == dataset.transitions.count else {
            throw BackupError.malformedBackup("duplicate transition id")
        }
        for transition in dataset.transitions {
            guard tripItemIDs.contains(transition.tripItemID) else {
                throw BackupError.malformedBackup("transition references missing trip item \(transition.tripItemID)")
            }
        }
    }

    /// Decodes and validates a backup. Throws `BackupError` for unreadable
    /// envelopes and domain replay errors for inconsistent ledgers.
    public static func decode(_ data: Data) throws -> PackDeckDataset {
        let envelope: Envelope
        do {
            envelope = try decoder().decode(Envelope.self, from: data)
        } catch let error as DecodingError {
            throw BackupError.malformedBackup(String(describing: error))
        }

        guard supportedFormatVersions.contains(envelope.formatVersion) else {
            throw BackupError.unsupportedFormatVersion(envelope.formatVersion)
        }
        try validateRelationalIntegrity(envelope.dataset)
        return envelope.dataset
    }

    /// Restores a backup into `store` transactionally (whole-dataset
    /// replace; see `PackDeckStore.replaceAll`).
    public static func restore(_ data: Data, into store: PackDeckStore) throws {
        let dataset = try decode(data)
        try store.replaceAll(with: dataset)
    }

    /// Summary of an uncommitted backup payload for user confirmation.
    public struct Preview: Equatable, Sendable {
        public let formatVersion: Int
        public let kitCount: Int
        public let tripCount: Int
        public let tripItemCount: Int
        public let transitionCount: Int

        public init(formatVersion: Int, kitCount: Int, tripCount: Int, tripItemCount: Int, transitionCount: Int) {
            self.formatVersion = formatVersion
            self.kitCount = kitCount
            self.tripCount = tripCount
            self.tripItemCount = tripItemCount
            self.transitionCount = transitionCount
        }
    }

    /// Previews a backup without touching the store or mutating state.
    public static func preview(_ data: Data) throws -> Preview {
        let dataset = try decode(data)
        let version = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Preview(
            formatVersion: version?["formatVersion"] as? Int ?? currentFormatVersion,
            kitCount: dataset.kits.count,
            tripCount: dataset.trips.count,
            tripItemCount: dataset.tripItems.count,
            transitionCount: dataset.transitions.count
        )
    }
}
