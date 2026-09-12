import SwiftUI

/// Hosts the bundled Total Service Pro HTML shell.
/// Real screens will replace `Resources/assets` from totalservicepro-web later.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            TSPWebView(resourceName: "index", subdirectory: "assets")
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HomeView()
}
