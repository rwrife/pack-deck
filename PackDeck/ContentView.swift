import SwiftUI

/// Root navigation surface. The kit library (issue #4) is the first slice;
/// trip building and the packing workspace (`PackWorkspaceLayout`, issue #5)
/// hang off this stack in later milestones.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            KitLibraryView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
}
