import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { KitLibraryView() }
                .tabItem { Label("Kits", systemImage: "bag") }
            NavigationStack { TripListView() }
                .tabItem { Label("Trips", systemImage: "suitcase") }
            NavigationStack { DataTransferView() }
                .tabItem { Label("Data", systemImage: "arrow.triangle.2.circlepath") }
                .accessibilityIdentifier("tab.data")
        }
    }
}

#Preview {
    ContentView().environment(AppStore())
}
