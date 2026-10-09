import SwiftUI

struct ContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Plain VStack rather than .safeAreaInset for the probe strip: an
        // inset over a TabView breaks tab-bar hit points while the soft
        // keyboard is up (proven in CI elsewhere).
        VStack(spacing: 0) {
            TabView {
                NavigationStack { KitLibraryView() }
                    .tabItem { Label("Kits", systemImage: "bag") }
                NavigationStack { TripListView() }
                    .tabItem { Label("Trips", systemImage: "suitcase") }
                NavigationStack { DataTransferView() }
                    .tabItem { Label("Data", systemImage: "arrow.triangle.2.circlepath") }
                    .accessibilityIdentifier("tab.data")
            }
            if ProcessInfo.processInfo.arguments.contains("--accessibility-probe") {
                // XCUITest seam: proves the requested Dynamic Type category
                // actually applied to this view (rendered category renders
                // as e.g. "accessibility5" for the AX5 token).
                Text("Dynamic Type: \(String(describing: dynamicTypeSize))")
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("accessibility.dynamicType")
            }
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

#Preview {
    ContentView().environment(AppStore())
}
