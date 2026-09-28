import SwiftUI
import PackDeckKit
import PackDeckStore

/// Skeleton root view. The kit-library vertical slice (issue #4) replaces
/// this; the real UI is routed through `PackWorkspaceLayout` (issue #5).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Pack Deck")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text(PackDeckKit.milestone)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(PackDeckStore.milestone)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
