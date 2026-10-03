import SwiftUI
import PackDeckKit

/// Kit library: lists every kit template with its item count, and offers
/// create / edit / delete. Deleting a kit that is still referenced by a trip's
/// build-time provenance warns first (items are copied into trips at build
/// time, so deletion is safe but irreversible).
struct KitLibraryView: View {
    @Environment(AppStore.self) private var store

    @State private var showNewKit = false
    @State private var kitPendingDeletion: KitTemplate?
    @State private var referencingTrips: [Trip] = []
    @State private var showDeleteWarning = false

    var body: some View {
        Group {
            if store.kits.isEmpty {
                emptyState
            } else {
                kitList
            }
        }
        .navigationTitle("Kits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewKit = true
                } label: {
                    Label("New Kit", systemImage: "plus")
                }
                .accessibilityIdentifier("kit.add")
                .accessibilityLabel("New Kit")
            }
        }
        .sheet(isPresented: $showNewKit) {
            NavigationStack {
                KitEditorView(kit: nil)
            }
        }
        .alert(
            "Delete kit?",
            isPresented: $showDeleteWarning,
            presenting: kitPendingDeletion
        ) { kit in
            Button("Delete", role: .destructive) {
                store.delete(id: kit.id)
                kitPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                kitPendingDeletion = nil
            }
        } message: { kit in
            Text(deleteWarningMessage(for: kit))
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Kits", systemImage: "bag")
        } description: {
            Text("Create a kit to save reusable packing lists — like carry-on tech or a weekender.")
        } actions: {
            Button {
                showNewKit = true
            } label: {
                Label("New Kit", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Hit-target contract (issue #4): ≥44pt touch height.
            .frame(minHeight: 44)
            .accessibilityIdentifier("kit.add.empty")
        }
    }

    private var kitList: some View {
        List {
            ForEach(store.kits) { kit in
                NavigationLink {
                    KitEditorView(kit: kit)
                } label: {
                    KitRow(kit: kit)
                }
                .accessibilityIdentifier("kit.row.\(kit.name)")
                .accessibilityLabel("\(kit.name), \(kit.items.count) item\(kit.items.count == 1 ? "" : "s")")
            }
            .onDelete(perform: requestDelete)
        }
    }

    private func requestDelete(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        let kit = store.kits[index]
        let refs = store.tripsReferencing(kitID: kit.id)
        if refs.isEmpty {
            store.delete(id: kit.id)
        } else {
            referencingTrips = refs
            kitPendingDeletion = kit
            showDeleteWarning = true
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { presented in if !presented { store.lastError = nil } }
        )
    }

    private func deleteWarningMessage(for kit: KitTemplate) -> String {
        let names = referencingTrips.map(\.name).joined(separator: ", ")
        return "\u{201C}\(kit.name)\u{201D} is used by \(referencingTrips.count) trip\(referencingTrips.count == 1 ? "" : "s") (\(names)). Kit items are copied into trips at build time, so deleting this kit won't remove items from those trips."
    }
}

/// One row in the kit list: name, item count, and optional notes preview.
private struct KitRow: View {
    let kit: KitTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kit.name)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Label("\(kit.items.count)", systemImage: "list.bullet")
                if let notes = kit.notes, !notes.isEmpty {
                    Text(notes)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        KitLibraryView()
    }
    .environment(AppStore())
}
