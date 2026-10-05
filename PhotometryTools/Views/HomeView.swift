import SwiftUI

/// Live Total Service Pro site. Bundled HTML loads only when the device is offline.
struct HomeView: View {
    var body: some View {
        TSPWebView(entry: .liveSite)
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService.shared)
        .environmentObject(BiometricSettings.shared)
        .environmentObject(BiometricUnlockController.shared)
}
