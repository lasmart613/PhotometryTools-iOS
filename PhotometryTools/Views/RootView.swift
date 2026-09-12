import SwiftUI

/// Signed-out: native login. Signed-in: tab shell + Home WKWebView.
struct RootView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        Group {
            if auth.isSignedIn {
                ContentView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: auth.isSignedIn)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthService.shared)
}
