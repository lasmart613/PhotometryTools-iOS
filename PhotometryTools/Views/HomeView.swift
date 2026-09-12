import SwiftUI

/// Hosts the bundled Total Service Pro HTML shell (synced from totalservicepro-web).
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
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
        .environmentObject(BiometricUnlockController.shared)
}
