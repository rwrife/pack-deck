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
    public static let currentFormatVersion: Int = 1

    /// Backup format versions this build can read.
    public static let supportedFormatVersions: Set<Int> = [1]

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
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    /// Decodes and validates a backup. Throws `BackupError` for unreadable
    /// envelopes and domain replay errors for inconsistent ledgers.
    public static func decode(_ data: Data) throws -> PackDeckDataset {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch let error as DecodingError {
            throw BackupError.malformedBackup(String(describing: error))
        }

        guard supportedFormatVersions.contains(envelope.formatVersion) else {
            throw BackupError.unsupportedFormatVersion(envelope.formatVersion)
        }
        return envelope.dataset
    }

    /// Restores a backup into `store` transactionally (whole-dataset
    /// replace; see `PackDeckStore.replaceAll`).
    public static func restore(_ data: Data, into store: PackDeckStore) throws {
        let dataset = try decode(data)
        try store.replaceAll(with: dataset)
    }
}
