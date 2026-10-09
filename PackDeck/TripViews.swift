import SwiftUI
import PackDeckKit

struct TripListView: View {
    @Environment(AppStore.self) private var store
    @State private var creating = false

    var body: some View {
        List {
            if store.trips.isEmpty {
                ContentUnavailableView("No Trips", systemImage: "suitcase", description: Text("Create a trip to start packing."))
            }
            ForEach(store.trips) { trip in
                NavigationLink {
                    PackWorkspaceLayout(trip: trip)
                } label: {
                    VStack(alignment: .leading) {
                        Text(trip.name).font(.headline)
                        if let summary = store.summary(for: trip) {
                            Text("\(summary.packed) of \(summary.totalItems) packed")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("trip.row.\(trip.name)")
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            Button { creating = true } label: { Label("New Trip", systemImage: "plus") }
                .accessibilityIdentifier("trip.add")
        }
        .sheet(isPresented: $creating) {
            NavigationStack { TripBuilderView() }
        }
        .onAppear { store.reload() }
    }
}

struct TripBuilderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: String?
    @State private var name = ""
    @State private var nights = 1
    @State private var laundry: LaundryAccess = .unknown
    @State private var tags = ""
    @State private var kitIDs: Set<UUID> = []
    @State private var adHocName = ""
    @State private var adHocItems: [AdHocItem] = []

    var body: some View {
        Form {
            Section("Trip") {
                TextField("Trip name", text: $name)
                    .focused($focusedField, equals: "name")
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("trip.name")
                    .accessibilityLabel("Trip name")
                Stepper("Nights: \(nights)", value: $nights, in: 1...365)
                    .accessibilityIdentifier("trip.nights")
                Picker("Laundry", selection: $laundry) {
                    Text("Unknown").tag(LaundryAccess.unknown)
                    Text("Available").tag(LaundryAccess.available)
                    Text("Unavailable").tag(LaundryAccess.unavailable)
                }
                TextField("Activity tags (comma separated)", text: $tags)
                    .focused($focusedField, equals: "tags")
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("trip.tags")
                    .accessibilityLabel("Activity tags, comma separated")
            }
            Section("Kits") {
                ForEach(store.kits) { kit in
                    Toggle(kit.name, isOn: Binding(
                        get: { kitIDs.contains(kit.id) },
                        set: { enabled in
                            if enabled { kitIDs.insert(kit.id) } else { kitIDs.remove(kit.id) }
                        }
                    ))
                    .accessibilityIdentifier("trip.kit.\(kit.name)")
                }
            }
            Section("Ad-hoc items") {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                layout {
                    TextField("Item name", text: $adHocName)
                        .focused($focusedField, equals: "adhoc")
                        .onSubmit { focusedField = nil }
                        .accessibilityIdentifier("trip.adhoc.name")
                        .accessibilityLabel("Ad-hoc item name")
                    Button("Add") {
                        adHocItems.append(AdHocItem(name: adHocName.trimmingCharacters(in: .whitespacesAndNewlines)))
                        adHocName = ""
                    }
                    .disabled(adHocName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("trip.adhoc.add")
                }
                ForEach(adHocItems.indices, id: \.self) { index in
                    Text(adHocItems[index].name)
                }
                .onDelete { adHocItems.remove(atOffsets: $0) }
            }
        }
        .navigationTitle("New Trip")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let selected = store.kits.filter { kitIDs.contains($0.id) }
                    if store.createTrip(name: name, nights: nights, laundry: laundry,
                                        tags: tags.split(separator: ",").map(String.init),
                                        kits: selected, adHoc: adHocItems) != nil {
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          (kitIDs.isEmpty && adHocItems.isEmpty))
                .accessibilityIdentifier("trip.create")
            }
        }
        .alert("Could not create trip", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) { Button("OK") {} } message: { Text(store.lastError ?? "") }
    }
}

/// Single seam for future dual-screen adaptation; current layout is one
/// iPhone column only, with no dependence on external displays.
struct PackWorkspaceLayout: View {
    let trip: Trip
    var body: some View { PackWorkspaceView(trip: trip) }
}

struct PackWorkspaceView: View {
    @Environment(AppStore.self) private var store
    let trip: Trip
    @State private var missingOnly = false
    @State private var kitFilter = "all"

    private var items: [TripItem] {
        store.tripItems.filter { item in
            item.tripID == trip.id &&
            (!missingOnly || store.status(for: item) == .missing) &&
            (kitFilter == "all" || (kitFilter == "adhoc" ? item.sourceKitID == nil : item.sourceKitID?.uuidString == kitFilter))
        }
    }

    var body: some View {
        List {
            Section("Progress") {
                if let summary = store.summary(for: trip) {
                    Text("\(summary.packed) of \(summary.totalItems) packed")
                        .accessibilityIdentifier("workspace.progress")
                }
                Toggle("Missing only", isOn: $missingOnly)
                    .accessibilityIdentifier("workspace.missingOnly")
                Picker("By kit", selection: $kitFilter) {
                    Text("All items").tag("all")
                    ForEach(trip.sourceKitIDs, id: \.self) { id in
                        Text(store.kits.first(where: { $0.id == id })?.name ?? "Deleted kit")
                            .tag(id.uuidString)
                    }
                    Text("Ad-hoc").tag("adhoc")
                }
                .accessibilityIdentifier("workspace.kitFilter")
            }
            Section("Packing list") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.headline)
                        Text("\(store.status(for: item).rawValue.capitalized) · \(item.recommendation.quantity) recommended")
                            .accessibilityIdentifier("workspace.status.\(item.name)")
                        Text("Reason: \(item.recommendation.reasonString.replacingOccurrences(of: "_", with: " "))")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Menu("Set status") {
                                ForEach([ItemStatus.packed, .missing, .omitted], id: \.self) { status in
                                    Button(status.rawValue.capitalized) { store.setStatus(status, for: item) }
                                }
                            }
                            .accessibilityIdentifier("workspace.setStatus.\(item.name)")
                            if store.status(for: item) != .planned {
                                Button("Undo") { store.undo(for: item) }
                                    .accessibilityIdentifier("workspace.undo.\(item.name)")
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(trip.name)
        .onAppear { store.reload() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) { Button("OK") {} } message: { Text(store.lastError ?? "") }
    }
}
