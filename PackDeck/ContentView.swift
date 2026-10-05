import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { KitLibraryView() }
                .tabItem { Label("Kits", systemImage: "bag") }
            NavigationStack { TripListView() }
                .tabItem { Label("Trips", systemImage: "suitcase") }
        }
    }
}

#Preview {
    ContentView().environment(AppStore())
}
