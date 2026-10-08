import SwiftUI
import PackDeckKit

/// Draft representation of a kit item for editing.
///
/// Mirrors `KitItem` but with mutable fields and a simpler category model
/// (empty string ↔ nil on save). Preserves the stable UUID so edits update
/// the same row rather than creating new ones.
struct EditableItem: Identifiable {
    let id: UUID
    var name: String
    var quantity: Int
    var category: String

    init(kitItem: KitItem) {
        self.id = kitItem.id
        self.name = kitItem.name
        self.quantity = kitItem.baseQuantity
        self.category = kitItem.category ?? ""
    }

    init() {
        self.id = UUID()
        self.name = ""
        self.quantity = 1
        self.category = ""
    }

    /// Converts the draft back to a domain `KitItem`. An empty category
    /// becomes `nil`; quantities below one are clamped to one.
    var kitItem: KitItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return KitItem(
            id: id,
            name: trimmedName,
            baseQuantity: min(99, max(1, quantity)),
            category: trimmedCategory.isEmpty ? nil : trimmedCategory
        )
    }
}

/// Kit editor: name, notes, and a list of items with quantity and optional
/// category. Supports add / edit / remove / reorder via `ForEach($items)`
/// (identity-stable bindings) plus the standard `EditButton`. For existing
/// kits, also offers delete — with a warning when trips still reference it.
struct KitEditorView: View {
    /// Focus tokens so the keyboard can be dismissed deterministically via
    /// the return key (onSubmit) — required for both good UX and stable UI
    /// tests over the bottom-bar toolbar.
    enum EditorFocus: Hashable {
        case name, notes, item(UUID)
    }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: EditorFocus?

    private let original: KitTemplate?

    @State private var name: String
    @State private var notes: String
    @State private var items: [EditableItem]
    @State private var referencingTrips: [Trip] = []
    @State private var showDeleteWarning = false

    init(kit: KitTemplate?) {
        self.original = kit
        _name = State(initialValue: kit?.name ?? "")
        _notes = State(initialValue: kit?.notes ?? "")
        _items = State(initialValue: (kit?.items ?? []).map { EditableItem(kitItem: $0) })
    }

    private var isNew: Bool { original == nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Kit") {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("kit.name")
                    .accessibilityLabel("Kit name")
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    // No upper lineLimit: caps truncate notes at large
                    // Dynamic Type sizes (issue #7 audit).
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("kit.notes")
                    .accessibilityLabel("Kit notes")
            }

            Section {
                ForEach($items) { $item in
                    ItemRow(item: $item, focusedField: $focusedField)
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)
            } header: {
                Text("Items")
            } footer: {
                if items.isEmpty {
                    Text("Add items with the Add Item button below. Swipe rows to delete, or tap Edit to reorder.")
                }
            }
        }
        .navigationTitle(isNew ? "New Kit" : "Edit Kit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                // Enlarge the hosted bar-button layout box so its AX/hit
                // frame measures ≥44pt (issue #4: every interactive control
                // ≥44x44). contentShape makes the whole box tappable.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("kit.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!canSave)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("kit.save")
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button {
                        addItem()
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                    // Same 44pt hit-target treatment as the bar buttons above
                    // (issue #4): the plain bottom-bar glyph measured 33x36.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("kit.item.add")
                    Spacer()
                    EditButton()
                        .accessibilityIdentifier("kit.edit")
                }
            }
            if !isNew {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        requestDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("kit.delete")
                }
            }
        }
        .alert(
            "Delete kit?",
            isPresented: $showDeleteWarning,
            presenting: original
        ) { kit in
            Button("Delete", role: .destructive) {
                if store.delete(id: kit.id) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { kit in
            Text(deleteWarningMessage(for: kit))
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { presented in if !presented { store.lastError = nil } }
        )
    }

    private func addItem() {
        items.append(EditableItem())
    }

    private func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        let draftItems = items
            .map(\.kitItem)
            .filter { !$0.name.isEmpty }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let kit: KitTemplate
        if let original {
            kit = KitTemplate(
                id: original.id,
                schemaVersion: original.schemaVersion,
                name: trimmedName,
                notes: notes.isEmpty ? nil : notes,
                items: draftItems,
                createdAt: original.createdAt,
                updatedAt: Date()
            )
        } else {
            kit = KitTemplate(
                name: trimmedName,
                notes: notes.isEmpty ? nil : notes,
                items: draftItems
            )
        }
        if store.save(kit) {
            dismiss()
        }
        // On failure the editor stays open; the shared error alert
        // (observed from AppStore.lastError) surfaces the reason.
    }

    private func requestDelete() {
        guard let original else { return }
        let refs = store.tripsReferencing(kitID: original.id)
        if refs.isEmpty {
            if store.delete(id: original.id) {
                dismiss()
            }
        } else {
            referencingTrips = refs
            showDeleteWarning = true
        }
    }

    private func deleteWarningMessage(for kit: KitTemplate) -> String {
        let names = referencingTrips.map(\.name).joined(separator: ", ")
        return "This kit is used by \(referencingTrips.count) trip\(referencingTrips.count == 1 ? "" : "s") (\(names)). Kit items are copied into trips at build time, so deleting this kit won't remove items from those trips."
    }
}

/// Custom quantity stepper: two 44pt buttons around a quantity readout.
///
/// SwiftUI's built-in `Stepper` hosts a UIKit control whose AX/hit frame
/// stays at ~32pt regardless of SwiftUI layout modifiers (measured 161x32
/// twice on CI), so the 44x44pt hit-target contract (issue #4) requires
/// first-party buttons. Identifiers live on the leaf controls only —
/// container-level identifiers cascade over child identifiers in the AX
/// hierarchy, which would make the buttons unreachable to XCUITest.
private struct QuantityStepper: View {
    @Binding var quantity: Int

    var body: some View {
        HStack(spacing: 8) {
            Button {
                quantity = max(1, quantity - 1)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("kit.item.decrement")
            .accessibilityLabel("Decrease quantity")
            .disabled(quantity <= 1)

            Text("Qty: \(quantity)")
                .monospacedDigit()
                .frame(minWidth: 44)
                .accessibilityIdentifier("kit.item.quantity")

            Button {
                quantity = min(99, quantity + 1)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("kit.item.increment")
            .accessibilityLabel("Increase quantity")
            .disabled(quantity >= 99)
        }
    }
}

/// One editable item row: name, quantity stepper, optional category.
private struct ItemRow: View {
    @Binding var item: EditableItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState.Binding var focusedField: KitEditorView.EditorFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Item name", text: $item.name)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .item(item.id))
                .onSubmit { focusedField = nil }
                .accessibilityIdentifier("kit.item.name")
                .accessibilityLabel("Item name")

            // At accessibility text sizes the horizontal row (stepper +
            // category field) squeezes into truncation; stack it instead.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                QuantityStepper(quantity: $item.quantity)

                TextField("Category", text: $item.category)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .item(item.id))
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("kit.item.category")
                    .accessibilityLabel("Category")
            }
        }
        .padding(.vertical, 4)
    }

}

#Preview("New Kit") {
    NavigationStack {
        KitEditorView(kit: nil)
    }
    .environment(AppStore())
}

#Preview("Edit Kit") {
    NavigationStack {
        KitEditorView(kit: KitTemplate(name: "Weekender", items: [
            KitItem(name: "Socks", baseQuantity: 2, category: "clothing"),
            KitItem(name: "Toothbrush", baseQuantity: 1),
        ]))
    }
    .environment(AppStore())
}
