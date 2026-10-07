import SwiftUI
import UniformTypeIdentifiers
import PackDeckStore

/// Local Files backup/restore and a share-sheet CSV checklist (M6 #6).
///
/// Features:
/// - Versioned JSON backup saved to Files app.
/// - Versioned JSON restore previewed first (shows kit/trip/item counts),
///   then replaces transactionally.
/// - CSV checklist exported via standard iOS share sheet.
/// - 100% offline, zero network access.
struct DataTransferView: View {
    @Environment(AppStore.self) private var app
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: TransferDocument?
    @State private var csvURL: URL?
    @State private var pendingData: Data?
    @State private var preview: BackupCodec.Preview?
    @State private var confirming = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Backup & Restore") {
                Button {
                    do {
                        let data = try app.backupJSON()
                        guard data.count <= 20_000_000 else { throw TransferError.tooLarge }
                        backup = TransferDocument(data: data)
                        exporting = true
                    } catch {
                        errorMessage = "Could not prepare backup: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Export JSON Backup", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("transfer.exportJSON")

                Button {
                    importing = true
                } label: {
                    Label("Import JSON Backup", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("transfer.importJSON")
            }

            Section("Checklist Export") {
                Button {
                    do {
                        let data = try app.checklistCSV()
                        let tempURL = FileManager.default.temporaryDirectory
                            .appending(path: "packdeck-checklist-\(UUID().uuidString).csv")
                        try data.write(to: tempURL, options: .atomic)
                        csvURL = tempURL
                    } catch {
                        errorMessage = "Could not prepare CSV: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Prepare CSV Checklist", systemImage: "tablecells")
                }
                .accessibilityIdentifier("transfer.prepareCSV")

                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Share CSV Checklist", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("transfer.shareCSV")
                }
            }
        }
        .navigationTitle("Data Transfer")
        .fileExporter(
            isPresented: $exporting,
            document: backup,
            contentType: .json,
            defaultFilename: "PackDeck-backup"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
            backup = nil
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let url = try result.get()
                let accessible = url.startAccessingSecurityScopedResource()
                defer {
                    if accessible { url.stopAccessingSecurityScopedResource() }
                }

                // Bound bytes actually read; fileSize metadata can be absent
                // or untrusted for a provider-backed Files URL.
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: 20_000_001) ?? Data()
                guard data.count <= 20_000_000 else { throw TransferError.tooLarge }

                let summary = try app.previewBackup(data)
                pendingData = data
                preview = summary
                confirming = true
            } catch {
                errorMessage = "Invalid backup: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Replace All Local Data?",
            isPresented: $confirming,
            titleVisibility: .visible,
            presenting: preview
        ) { _ in
            Button("Replace All Data", role: .destructive) {
                guard let data = pendingData else { return }
                do {
                    try app.restoreBackup(data)
                } catch {
                    errorMessage = "Restore failed: \(error.localizedDescription)"
                }
                pendingData = nil
                preview = nil
                confirming = false
            }
            Button("Cancel", role: .cancel) {
                pendingData = nil
                preview = nil
                confirming = false
            }
        } message: { summary in
            Text("Backup contains \(summary.kitCount) kits, \(summary.tripCount) trips, \(summary.tripItemCount) trip items, and \(summary.transitionCount) status events.\n\nAll existing data on this iPhone will be replaced transactionally. This action cannot be undone.")
        }
        .alert("Data Transfer Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private enum TransferError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "Backup exceeds the 20 MB import limit." }
}

private struct TransferDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
